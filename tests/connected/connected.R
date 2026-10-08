# Mutable lifecycle-only test harness. Runs the original integrated launcher.
# No source/ready/queue/UI/server function override or fabricated health response.
(function() {
  args <- commandArgs(TRUE); stopifnot(length(args) == 2L)
  cfg <- jsonlite::fromJSON(args[[1L]], simplifyVector = FALSE)
  output <- args[[2L]]; stopifnot(!file.exists(output), !dir.exists(cfg$workspace))
  dir.create(output, recursive = TRUE)
  old_wd <- getwd(); child <- NULL; passed <- FALSE; forced <- FALSE; first <- NULL
  checks <- character(); startup <- NULL; normal_stop_requested <- FALSE
  began <- proc.time()[["elapsed"]]
  write <- function(value, name) writeLines(jsonlite::toJSON(value, auto_unbox = TRUE,
    pretty = TRUE, null = "null", digits = NA), file.path(output, name), useBytes = TRUE)
  check <- function(name, ok) {
    if (!isTRUE(ok)) stop(name, call. = FALSE)
    checks <<- c(checks, name)
  }
  owned <- function(services) {
    live <- Filter(function(process) !is.null(process) && process$is_alive(), services$owned)
    identities <- list()
    if (length(live)) {
      pids <- vapply(live, function(process) as.character(process$get_pid()), character(1))
      observed <- processx::run(cfg$python, c("-B", cfg$identity_helper, pids),
        timeout = 5, error_on_status = FALSE, windows_hide_window = TRUE)
      if (!identical(observed$status, 0L)) stop("Cannot retain original service process identities: ", observed$stderr)
      identities <- jsonlite::fromJSON(observed$stdout, simplifyVector = FALSE)$identities
    }
    lapply(names(services$owned), function(name) {
      process <- services$owned[[name]]
      active <- !is.null(process) && process$is_alive()
      identity <- if (active) Filter(function(row) identical(as.numeric(row$pid), as.numeric(process$get_pid())), identities) else list()
      if (active && length(identity) != 1L) stop("Original service identity changed during observation.")
      row <- if (active) identity[[1L]] else NULL
      list(service = name, pid = if (is.null(process)) NULL else process$get_pid(), alive = active,
        creation_decimal = if (active) row$creation_decimal else NULL,
        creation_clock = if (active) row$creation_clock else NULL,
        command = if (active) row$command else NULL,
        exit_status = if (is.null(process)) NULL else process$get_exit_status())
    })
  }
  health <- function() {
    previous <- getOption("timeout"); options(timeout = 1); on.exit(options(timeout = previous))
    connection <- url(paste0("http://127.0.0.1:", cfg$participant_port, "/api/health"), open = "rb", method = "libcurl")
    on.exit(close(connection), add = TRUE)
    raw <- readBin(connection, "raw", n = 4096); text <- rawToChar(raw); Encoding(text) <- "UTF-8"
    list(raw = text, sha256 = digest::digest(raw, algo = "sha256", serialize = FALSE), value = brohn_parse(text))
  }
  on.exit({
    if (!is.null(child) && child$is_alive()) {
      forced <- TRUE
      tryCatch({child$kill_tree(); child$wait(5000)}, error = function(e) {
        if (is.null(first)) first <<- list(message = conditionMessage(e), phase = "browser_cleanup")
      })
    }
    services <- getOption("brohn.services")
    write(list(passed = passed && !forced, checks = as.list(checks), first_failure = first,
      elapsed_s = proc.time()[["elapsed"]] - began, supervisor_forced = forced,
      normal_launcher_stop_requested = normal_stop_requested,
      browser_closed = is.null(child) || !child$is_alive(), startup = startup,
      service_events = if (is.null(services)) NULL else services$events,
      stopped = if (is.null(services)) NULL else services$stopped,
      owned_after = if (is.null(services)) NULL else owned(services)), "RESULTS.json")
    setwd(old_wd)
  }, add = TRUE)
  tryCatch({
    stopifnot(cfg$researcher_port != cfg$participant_port)
    Sys.setenv(BROHN_WORKSPACE = cfg$workspace, BROHN_APP_MODE = "platform",
      RESEARCH_PLATFORM_PORT = as.character(cfg$researcher_port),
      BROHN_PARTICIPANT_PORT = as.character(cfg$participant_port), BROHN_HOSTED_PROFILE = "",
      BROHN_PYTHON = cfg$python)
    setwd(cfg$installation)
    write(list(root = cfg$root, chrome = cfg$chrome, package_json = cfg$package_json,
      url = paste0("http://127.0.0.1:", cfg$researcher_port, "/"),
      participant_port = cfg$participant_port, output = file.path(output, "browser")), "BROWSER-CONFIG.json")
    child <- processx::process$new(cfg$node, c(cfg$browser_test, file.path(output, "BROWSER-CONFIG.json")),
      stdout = file.path(output, "browser.stdout.log"), stderr = file.path(output, "browser.stderr.log"),
      cleanup_tree = TRUE, windows_hide_window = TRUE)
    observe <- function() {
      services <- getOption("brohn.services")
      if (is.null(startup) && !is.null(services)) {
        startup <<- list(workspace_id = services$workspace_id, workspace_root = services$root,
          participant_ready = brohn_participant_ready(services$workspace_id, cfg$participant_port),
          participant_health = health(),
          acquisition_ready = brohn_acquisition_ready(services$root, services$workspace_id),
          owned = owned(services), logs = services$logs)
        write(startup, "ACTUAL-SERVICES.json")
      }
      if (!child$is_alive()) {
        normal_stop_requested <<- TRUE
        shiny::stopApp(); return(invisible(NULL))
      }
      if (proc.time()[["elapsed"]] - began > 240) {
        forced <<- TRUE; child$kill_tree(); shiny::stopApp(); return(invisible(NULL))
      }
      later::later(observe, .1)
    }
    later::later(observe, .1)
    # Exact ordinary entry point: library/publication checks and all service
    # ownership, readiness, monitoring and cleanup remain production behavior.
    source("scripts/run-brohn.R", local = .GlobalEnv, encoding = "UTF-8")
    child$wait(5000)
    check("ordinary launcher stops after browser completes within original deadline", normal_stop_requested && !forced && !child$is_alive())
    check("real participant and acquisition services became ready for same workspace", !is.null(startup) &&
      isTRUE(startup$participant_ready) && isTRUE(startup$acquisition_ready) &&
      identical(startup$participant_health$value$service, "brohn-participant") &&
      identical(startup$participant_health$value$workspace_id, startup$workspace_id))
    check("all three production services were owned and alive", length(startup$owned) == 3L &&
      setequal(vapply(startup$owned, `[[`, character(1), "service"), c("participant", "acquisition", "worker")) &&
      all(vapply(startup$owned, function(x) isTRUE(x$alive), logical(1))))
    result <- jsonlite::fromJSON(file.path(output, "browser/RESULTS.json"), simplifyVector = FALSE)
    check("normal researcher Publish participant and automatic report journey passed", identical(child$get_exit_status(), 0L) && isTRUE(result$passed))
    services <- getOption("brohn.services")
    check("ordinary services required no unreported restart or external takeover", all(vapply(services$generations,
      function(value) identical(value, 1L), logical(1))) &&
      !any(vapply(services$events, function(event) event$event %in% c("unexpected_exit", "restart_failed", "restart_started", "compatible_external_service_reused"), logical(1))))
    # Join the production stop requests; do not issue any additional stop/kill.
    for (process in services$owned) if (process$is_alive()) process$wait(5000)
    check("ordinary launcher stopped its exact owned service set", isTRUE(services$stopped) &&
      all(vapply(services$owned, function(process) !process$is_alive(), logical(1))))
    check("browser and ordinary shutdown leave time for bounded document checks", proc.time()[["elapsed"]] - began < 240)
    source(file.path(dirname(cfg$browser_test), "document-guards.R"), local = environment(), encoding = "UTF-8")
    guards <- brohn_test_document_guards(cfg$installation, file.path(output, "document-guards"))
    check("controlled original R document guards pass within original240-second budget", isTRUE(guards$passed) && proc.time()[["elapsed"]] - began < 240)
    passed <- TRUE
  }, error = function(e) first <<- list(message = conditionMessage(e), call = paste(deparse(conditionCall(e)), collapse = " ")))
  if (!passed) stop(first$message, call. = FALSE)
})()
