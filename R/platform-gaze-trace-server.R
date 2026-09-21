# Connected saved-trace explorer. Complete-file verification runs off the Shiny
# event loop and holds native source guards until the view/download is closed.
.brohn_gt_action <- function(label, action, pin, primary = FALSE) shiny::tags$button(type = "button",
  class = if (primary) "btn btn-primary" else "btn btn-outline-secondary", `data-gaze-trace-action` = action,
  `data-gaze-trace-payload` = brohn_json(pin), label)

.brohn_gt_exposure_key <- function(identity) brohn_hash(lapply(c("participant_id", "session_id", "stimulus_id", "exposure_id"), function(field) identity[[field]]))
brohn_gaze_trace_match_exposure <- function(tables, selector, report_hash) {
  if (!brohn_text(selector, 200)) return(NULL)
  matches <- Filter(function(t) identical(paste(report_hash, .brohn_gt_exposure_key(t$identity), sep = ":"), selector), tables)
  brohn_require(length(matches) <= 1L, "The source trace catalog has duplicate exposure identities.")
  if (length(matches)) matches[[1L]] else NULL
}

brohn_gaze_trace_report_ui <- function(report) {
  if (!identical(report$analysis$kind, "gaze") || !identical(report$analysis$parameters$input, "raw_gaze_samples")) return(NULL)
  has_trace <- identical(report$analysis$parameters$trace_profile, "gaze-pupil-source-trace/1.0")
  mapped <- brohn_text(report$provenance$mapping$pupil_column, 500) || brohn_text(report$provenance$mapping$blink_column, 500)
  if (!has_trace && !mapped) return(NULL)
  shiny::tagList(
    if (has_trace) brohn_command("Explore pupil and blink traces", "open_gaze_trace", list(report_id = report$id, report_hash = brohn_hash(report))),
    if (!has_trace && any(vapply(report$analysis$features, function(e) identical(e$record_type, "source_labelled_blink"), logical(1))))
      shiny::p(brohn_gaze_blink_policy_disclosure(report$analysis$parameters)),
    if (!has_trace) shiny::p("This historical report has no complete pupil/blink trace. A fresh analysis of its selected original source is needed to retain samples."),
    shiny::tags$script(src = "gaze-trace-ui.js"),
    shiny::tags$style(shiny::HTML(".brohn-gaze-trace,.brohn-gaze-trace-controls{min-width:0;max-width:100%}.brohn-gaze-trace-controls button,.brohn-gaze-trace-controls input,.brohn-gaze-trace-controls select,.brohn-gaze-trace summary,.brohn-gaze-trace a{min-height:44px}.brohn-gaze-trace summary{padding:.7rem;cursor:pointer}.brohn-gaze-trace table th,.brohn-gaze-trace table td{white-space:nowrap;padding:.5rem}.brohn-gaze-trace-controls .form-group{min-width:0}.brohn-gaze-trace p{overflow-wrap:anywhere}")),
    shiny::uiOutput("gaze_trace_progress"), shiny::uiOutput("gaze_trace_controls"), shiny::uiOutput("gaze_trace_window"),
    shiny::uiOutput("gaze_trace_plot"), shiny::uiOutput("gaze_trace_downloads"))
}

brohn_install_gaze_trace_server <- function(input, output, session, store, state, attempt, message, prepare_download,
    register_resource = function(name, data, filter) session$registerDataObj(name, data, filter)) {
  active <- shiny::reactiveVal(NULL); catalog <- shiny::reactiveVal(NULL); preview <- shiny::reactiveVal(NULL)
  catalog_job <- shiny::reactiveVal(NULL); preview_job <- shiny::reactiveVal(NULL)
  issue <- shiny::reactiveVal(NULL); checking <- shiny::reactiveVal(FALSE); links <- shiny::reactiveVal(NULL)
  checks <- new.env(parent = emptyenv())
  release <- function(which) {
    check <- checks[[which]]
    if (!is.null(check)) {
      if (!is.null(check$process) && check$process$is_alive()) check$process$kill_tree()
      for (g in check$guards) .brohn_qexplorer_release(g)
    }
    checks[[which]] <- NULL
  }
  clear_preview <- function() {preview(NULL); preview_job(NULL); release("preview"); links(NULL)}
  clear <- function() {clear_preview(); release("catalog"); catalog(NULL); catalog_job(NULL); active(NULL); checking(FALSE)}
  session$onSessionEnded(function() {release("catalog"); release("preview")})
  shiny::observeEvent(list(state$page, state$report_id), {clear(); issue(NULL)}, ignoreInit = FALSE, priority = 120)
  guard <- function() tryCatch({
    p <- active()
    brohn_require(!is.null(p) && identical(state$page, "report") && identical(state$report_id, p$report_id), "Reopen the pupil/blink explorer for this report.")
    hash <- .brohn_qexplorer_catalog(store, "report", p$report_id, p$revision, p$project_id)
    brohn_require(identical(hash, p$catalog_hash), "The selected saved report or project authority changed.")
    brohn_project(store, p$project_id)
    for (which in c("catalog", "preview")) {
      record <- if (which == "catalog") catalog() else preview()
      if (!is.null(record)) {
        brohn_gaze_trace_record(store, record$id, brohn_hash(record$body), verify = FALSE)
        held <- checks[[which]]
        if (!is.null(held)) for (g in held$guards) .Call(g$native$check, g$pointer)
      }
    }
    p
  }, error = function(e) {clear(); stop(e)})
  protect <- function(fn) attempt(function() {issue(NULL); tryCatch(fn(), error = function(e) {issue(conditionMessage(e)); stop(e)})})
  table <- shiny::reactive({
    c <- catalog(); shiny::req(c, input$gaze_trace_table)
    found <- Filter(function(t) identical(t$table_id, input$gaze_trace_table), c$body$result$tables)
    shiny::req(length(found) == 1L); found[[1L]]
  })
  form <- function(c, t) paste(c$id, c$revision, brohn_hash(c$body), t$table_id, sep = ":")
  queue_preview <- function(c, t, start, end, retry = FALSE) {
    p <- guard(); clear_preview()
    selection <- list(table_id = t$table_id, identity = t$identity, start_ms = start, end_ms = end)
    j <- brohn_queue_gaze_trace(store, p$report_id, p$revision, p$report_hash, p$project_id,
      catalog = list(id = c$id, revision = c$revision, hash = brohn_hash(c$body)), selection = selection, retry = retry)
    preview_job(j); message("Preparing every pupil/blink source row in the selected time window.")
  }
  start_check <- function(which, record) {
    release(which)
    source <- brohn_gaze_trace_job_input(store, list(operation = record$body$operation, request = record$body$request), verify = FALSE)
    refs <- c(source$source_objects, list(list(hash = record$body$result_object$hash, bytes = record$body$result_object$size)))
    refs <- refs[!duplicated(vapply(refs, `[[`, character(1), "hash"))]
    source$source_objects <- refs; held <- brohn_hold_gaze_trace_sources(store, source); success <- FALSE
    on.exit(if (!success) for (g in held) .brohn_qexplorer_release(g), add = TRUE)
    paths <- lapply(refs, function(r) list(path = brohn_object_path(store, r$hash, verify = FALSE), sha256 = r$hash))
    code <- paste(c("import hashlib,json,sys", "for item in json.loads(sys.argv[1]):", " h=hashlib.sha256()",
      " with open(item['path'],'rb') as f:", "  for block in iter(lambda:f.read(1048576),b''):h.update(block)",
      " if h.hexdigest()!=item['sha256']:raise RuntimeError('Saved source bytes changed.')", "print('verified')"), collapse = "\n")
    process <- processx::process$new(.brohn_publication_python(), c("-B", "-c", code, brohn_json(paths)),
      stdout = "|", stderr = "|", cleanup_tree = TRUE, windows_hide_window = TRUE)
    checks[[which]] <- list(process = process, guards = held, record = record, started = Sys.time())
    success <- TRUE; checking(TRUE)
  }
  shiny::observeEvent(input$open_gaze_trace, protect(function() {
    cmd <- input$open_gaze_trace
    brohn_require(identical(state$page, "report") && identical(cmd$report_id, state$report_id), "Open this saved gaze report first.")
    r <- brohn_get_entity(store, "report", state$report_id)
    brohn_require(identical(cmd$report_hash, brohn_hash(r$body)), "This report changed. Open its current saved revision.")
    clear()
    active(list(report_id = r$id, revision = r$revision, report_hash = brohn_hash(r$body), project_id = r$project_id,
      catalog_hash = .brohn_qexplorer_catalog(store, "report", r$id, r$revision, r$project_id)))
    catalog_job(brohn_queue_gaze_trace(store, r$id, r$revision, brohn_hash(r$body), r$project_id))
    message("Reading the complete saved pupil/blink catalog in the background.")
  }))
  shiny::observe({
    p <- active(); if (is.null(p)) return(); shiny::invalidateLater(1000, session)
    tryCatch(shiny::isolate({
      guard()
      for (which in c("catalog", "preview")) {
        slot <- if (which == "catalog") catalog_job else preview_job
        ready <- if (which == "catalog") catalog else preview
        j <- slot(); if (is.null(j)) next
        fresh <- brohn_get_job(store, j$id); slot(fresh)
        if (!identical(fresh$status, "succeeded") || is.null(fresh$result$gaze_trace_view_id) || !is.null(ready())) next
        check <- checks[[which]]
        if (is.null(check)) {
          r <- brohn_gaze_trace_record(store, fresh$result$gaze_trace_view_id, verify = FALSE)
          brohn_require(.brohn_gt_same(r$body$request, fresh$request), "This saved trace belongs to another queued selection.")
          start_check(which, r)
        } else if (!check$process$is_alive()) {
          brohn_require(identical(check$process$get_exit_status(), 0L) && identical(trimws(check$process$read_all_output()), "verified"),
            "Saved trace bytes failed verification. Reopen the report and prepare a new view.")
          for (g in check$guards) .Call(g$native$check, g$pointer)
          # Small retained envelopes are compared after background whole-file
          # verification; no multi-GiB artifact is hashed on this event loop.
          retained <- brohn_read_json_file(brohn_object_path(store, check$record$body$result_object$hash, verify = FALSE))
          brohn_require(.brohn_gt_same(retained, check$record$body[setdiff(names(check$record$body), "result_object")]), "Saved trace catalog differs from its retained result.")
          source <- brohn_gaze_trace_job_input(store, list(operation = check$record$body$operation, request = check$record$body$request), verify = FALSE)
          brohn_validate_gaze_trace_result(check$record$body$result, source)
          check$process <- NULL; checks[[which]] <- check; ready(check$record)
        } else brohn_require(as.numeric(difftime(Sys.time(), check$started, units = "secs")) < 900, "Trace verification took too long. Close the view and retry.")
      }
      checking(any(vapply(as.list(checks), function(check) !is.null(check$process), logical(1))))
    }), error = function(e) {clear(); issue(conditionMessage(e))})
  })
  output$gaze_trace_controls <- shiny::renderUI({
    c <- catalog(); if (is.null(c)) return(NULL)
    matching <- brohn_gaze_trace_match_exposure(c$body$result$tables, input$gaze_report_exposure, active()$report_hash)
    choices <- stats::setNames(vapply(c$body$result$tables, `[[`, character(1), "table_id"),
      vapply(c$body$result$tables, function(t) paste(t$identity$participant_id, t$identity$session_id, t$identity$exposure_id, t$identity$stimulus_id, sep = " | "), character(1)))
    shiny::div(class = "brohn-gaze-trace-controls", shiny::selectInput("gaze_trace_table", "Participant, session, exposure and stimulus", choices,
      selected = if (!is.null(matching)) matching$table_id else unname(choices)[[1L]], selectize = FALSE))
  })
  shiny::observeEvent(input$gaze_report_exposure, protect(function() {
    c <- catalog(); if (is.null(c)) return(invisible(NULL))
    clear_preview()
    matching <- brohn_gaze_trace_match_exposure(c$body$result$tables, input$gaze_report_exposure, guard()$report_hash)
    if (is.null(matching)) {
      issue("The selected gaze exposure has no matching complete pupil/blink trace. Choose an explicitly labelled trace exposure below.")
    } else if (identical(input$gaze_trace_table, matching$table_id)) {
      queue_preview(c, matching, matching$initial_window$start_ms, matching$initial_window$end_ms)
    } else shiny::updateSelectInput(session, "gaze_trace_table", selected = matching$table_id)
  }), ignoreInit = TRUE, priority = 100)
  shiny::observeEvent(table(), protect(function() {
    c <- catalog(); t <- table(); queue_preview(c, t, t$initial_window$start_ms, t$initial_window$end_ms)
  }), ignoreInit = FALSE)
  output$gaze_trace_window <- shiny::renderUI({
    c <- catalog(); shiny::req(c); t <- table(); pin <- list(catalog_id = c$id, catalog_hash = brohn_hash(c$body), table_id = t$table_id)
    shiny::div(class = "brohn-gaze-trace-controls", `data-gaze-trace-form` = form(c, t),
      shiny::p(paste("Complete source:", t$rows, "rows from", .brohn_gaze_trace_number(t$start_ms), "to", .brohn_gaze_trace_number(t$end_ms), "ms.")),
      if (t$rows > 5000) shiny::p("The initial view uses the first 5,000 actual source rows. Select another time window to inspect later observations."),
      shiny::div(class = "brohn-form-grid", shiny::textInput("gaze_trace_start", "Start source time (ms)", .brohn_gaze_trace_number(t$initial_window$start_ms)),
        shiny::textInput("gaze_trace_end", "End source time (ms)", .brohn_gaze_trace_number(t$initial_window$end_ms))),
      shiny::checkboxInput("gaze_trace_full", "Request the complete recorded range", FALSE),
      .brohn_gt_action("Show pupil and blink window", "preview", pin, TRUE), .brohn_gt_action("Close pupil and blink traces", "close", pin))
  })
  shiny::observeEvent(input$gaze_trace_dirty, {
    cmd <- input$gaze_trace_dirty; c <- catalog()
    if (!is.null(c) && identical(cmd$form, form(c, table()))) {preview(NULL); links(NULL); release("preview"); preview_job(NULL)}
  }, priority = 100)
  shiny::observeEvent(input$gaze_trace_action, protect(function() {
    cmd <- input$gaze_trace_action; p <- guard()
    if (identical(cmd$action, "close")) {clear(); return(invisible(NULL))}
    if (cmd$action %in% c("retry", "cancel")) {
      slot <- if (identical(cmd$which, "catalog")) catalog_job else preview_job
      j <- slot(); brohn_require(!is.null(j) && identical(j$id, cmd$job_id) && identical(j$request$report_hash, p$report_hash), "Use this view's current processing action.")
      if (cmd$action == "cancel") {brohn_cancel_job(store, j$id); slot(brohn_get_job(store, j$id)); return(invisible(NULL))}
      brohn_require(j$status %in% c("failed", "cancelled"), "Only failed or cancelled trace processing can be retried.")
      r <- j$request; slot(brohn_queue_gaze_trace(store, r$report_id, r$report_revision, r$report_hash, r$project_id, r$catalog, r$selection, retry = TRUE)); return(invisible(NULL))
    }
    c <- catalog(); t <- table()
    brohn_require(!is.null(c) && identical(cmd$catalog_id, c$id) && identical(cmd$catalog_hash, brohn_hash(c$body)) && identical(cmd$table_id, t$table_id) &&
      identical(cmd$fields$form, form(c, t)), "Wait for the exact selected exposure's current window controls.")
    parse_number <- function(x) {
      brohn_require(brohn_text(x, 100) && grepl("^[+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$", x), "Enter finite nonnegative source times in milliseconds.")
      value <- as.numeric(x); brohn_require(brohn_number(value, 0, 1e12), "Enter finite supported source times."); value
    }
    brohn_require(identical(cmd$action, "preview") && is.logical(cmd$fields$full) && length(cmd$fields$full) == 1L, "Choose the current trace window action.")
    queue_preview(c, t, if (cmd$fields$full) NULL else parse_number(cmd$fields$start), if (cmd$fields$full) NULL else parse_number(cmd$fields$end))
  }))
  output$gaze_trace_progress <- shiny::renderUI(shiny::div(class = "brohn-gaze-trace-controls",
    if (!is.null(issue())) shiny::p(role = "alert", issue()), if (checking()) shiny::p(role = "status", "Verifying saved source bytes in the background."),
    lapply(c("catalog", "preview"), function(which) {
      j <- if (which == "catalog") catalog_job() else preview_job()
      if (is.null(j) || identical(j$status, "succeeded")) return(NULL)
      shiny::div(role = "status", shiny::p(switch(j$status, queued = "Pupil/blink view queued.", running = "Reading the complete saved trace.",
        failed = paste("Trace processing needs attention:", j$error$message), cancelled = "Trace processing cancelled; original report retained.", j$status)),
        if (j$status %in% c("queued", "running")) .brohn_gt_action("Cancel trace processing", "cancel", list(which = which, job_id = j$id)),
        if (j$status %in% c("failed", "cancelled")) .brohn_gt_action("Retry trace processing", "retry", list(which = which, job_id = j$id)))
    })))
  output$gaze_trace_plot <- shiny::renderUI({r <- preview(); if (is.null(r)) return(NULL); brohn_gaze_trace_ui(r$body$result)})
  shiny::observeEvent(preview(), {
    r <- preview(); if (is.null(r)) return(); token <- brohn_token()
    kinds <- c("complete", "window", if (identical(r$body$result$status, "available")) "svg")
    urls <- lapply(kinds, function(kind) {
      uri <- register_resource(paste0("brohn-gaze-trace-", kind), list(token = token, id = r$id, hash = brohn_hash(r$body), kind = kind),
        function(data, req) shiny::isolate(tryCatch({
          brohn_require(req$REQUEST_METHOD %in% c("GET", "HEAD") && identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING, ""))$trace_key, data$token), "This trace download is no longer active.")
          guard(); saved <- preview(); held <- checks[["preview"]]
          brohn_require(!is.null(saved) && identical(saved$id, data$id) && identical(brohn_hash(saved$body), data$hash) && !is.null(held) && is.null(held$process), "Reopen this exact verified trace window.")
          for (g in held$guards) .Call(g$native$check, g$pointer)
          if (data$kind == "svg") return(structure(list(status = 200L, content_type = "image/svg+xml",
            content = brohn_gaze_trace_export_svg(saved$body$result), headers = list("Content-Disposition" = paste0('attachment; filename="', data$id, '-trace.svg"'),
              "Cache-Control" = "no-store", "X-Content-Type-Options" = "nosniff")), class = "httpResponse"))
          ref <- if (data$kind == "complete") list(hash = saved$body$request$artifact$sha256) else saved$body$result_object
          path <- brohn_object_path(store, ref$hash, verify = FALSE)
          structure(list(status = 200L, content_type = if (data$kind == "complete") "application/x-ndjson" else "application/json",
            content = list(file = path, owned = FALSE), headers = list("Content-Disposition" = paste0('attachment; filename="', data$id, if (data$kind == "complete") '-complete.ndjson"' else '-window.json"'),
              "Cache-Control" = "no-store", "X-Content-Type-Options" = "nosniff")), class = "httpResponse")
        }, error = function(e) structure(list(status = 404L, content_type = "text/plain", content = "This exact trace download is unavailable. Reopen its saved report."), class = "httpResponse"))))
      paste0(uri, "&trace_key=", token)
    })
    names(urls) <- kinds; links(urls)
  }, ignoreNULL = TRUE)
  output$gaze_trace_downloads <- shiny::renderUI({urls <- links(); if (is.null(urls)) return(NULL)
    shiny::div(class = "brohn-gaze-trace", if (!is.null(urls$svg)) shiny::a(class = "btn btn-outline-secondary", href = urls$svg, download = "gaze-trace.svg", "Download trace chart"),
      shiny::a(class = "btn btn-outline-secondary", href = urls$window, download = "gaze-window.json", "Download exact window and support"),
      shiny::a(class = "btn btn-outline-secondary", href = urls$complete, download = "complete-gaze-trace.ndjson", "Download complete source trace"))})
  invisible(list(clear = clear, catalog = catalog, preview = preview, active = active))
}
