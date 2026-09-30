brohn_participant_ready <- function(workspace_id, port = Sys.getenv("BROHN_PARTICIPANT_PORT", "3840")) {
  previous <- getOption("timeout"); options(timeout = 1); on.exit(options(timeout = previous))
  tryCatch({
    connection <- url(paste0("http://127.0.0.1:", port, "/api/health"), open = "rb", method = "libcurl")
    on.exit(close(connection), add = TRUE)
    text <- rawToChar(readBin(connection, "raw", n = 4096)); Encoding(text) <- "UTF-8"
    result <- brohn_parse(text)
    identical(result$service, "brohn-participant") && identical(result$workspace_id, workspace_id)
  }, error = function(e) FALSE, warning = function(w) FALSE)
}
.brohn_runtime_wait_ready <- function(state, name, probe, timeout_s = 15) {
  brohn_require(brohn_number(timeout_s,.1,15),"Service readiness requires a bounded startup deadline.")
  child<-state$owned[[name]];started<-proc.time()[["elapsed"]];last<-list(status="starting",ready=FALSE,error=NULL)
  fail<-function(reason) {
    elapsed<-proc.time()[["elapsed"]]-started
    exit_code<-child$get_exit_status();log<-state$logs[[name]]$stderr
    detail<-paste0(name," service ",reason," after ",format(round(elapsed,2),trim=TRUE)," seconds.",
      if(!is.null(exit_code))paste0(" Exit code: ",exit_code,".")else"",
      " Last readiness state: ",last$status,".",if(!is.null(last$error))paste0(" ",last$error)else"",
      " Inspect its owned service log: ",log)
    brohn_service_event(state,list(service=name,event="startup_failed",reason=reason,elapsed_s=elapsed,
      readiness_status=last$status,exit_code=exit_code,log=log))
    brohn_stop(detail)
  }
  repeat {
    last<-probe()
    elapsed<-proc.time()[["elapsed"]]-started
    if(elapsed>=timeout_s)fail("did not become ready before its startup deadline")
    if(isTRUE(last$ready)) {
      # A compatible same-workspace service may win a concurrent launch. It
      # remains external only after a fresh probe following our child's exit.
      if(!child$is_alive()) {
        last<-probe()
        if(proc.time()[["elapsed"]]-started>=timeout_s)fail("did not become ready before its startup deadline")
        if(!isTRUE(last$ready))fail("exited before readiness")
        if(name=="acquisition"&&(is.null(last$value$process$pid)||identical(as.numeric(last$value$process$pid),as.numeric(child$get_pid()))))
          fail("exited before verified replacement readiness")
        state$owned[[name]]<-NULL
      }
      brohn_service_event(state,list(service=name,event="startup_ready",elapsed_s=proc.time()[["elapsed"]]-started,
        owned=!is.null(state$owned[[name]])))
      return(invisible(TRUE))
    }
    if(!child$is_alive())fail("exited before readiness")
    remaining<-timeout_s-elapsed
    if(remaining<=0)fail("did not become ready before its startup deadline")
    Sys.sleep(min(.1,remaining))
  }
}
brohn_start_services <- function(root, participant_port = 3840L) {
  brohn_require(brohn_number(participant_port, 1024, 65535, TRUE), "Choose a participant port between 1024 and 65535.")
  profile <- brohn_hosted_profile()
  if (!is.null(profile)) brohn_require(identical(normalizePath(root, winslash="/", mustWork=TRUE), profile$workspace_root) &&
    participant_port == profile$participant_port, "Service startup must match the configured hosted workspace and internal participant port.")
  publication<-brohn_publication_readiness()
  brohn_require(isTRUE(publication$ready),paste("Report publication is not ready.",publication$message,publication$action))
  store <- brohn_open_store(root); on.exit(brohn_close_store(store), add = TRUE)
  store <- brohn_hosted_bind_store(store, profile, participant=TRUE)
  brohn_initialise_library(store)
  state <- new.env(parent = emptyenv()); state$owned <- list(); state$root <- store$root
  state$stopped <- FALSE; state$scheduled <- FALSE; state$participant_port <- participant_port
  state$specs <- list(); state$generations <- list(); state$failures <- list(); state$next_attempt <- list(); state$started <- list(); state$logs <- list()
  state$last_error <- list(); state$events <- list(); state$session_id <- brohn_id("runtime"); state$snapshot <- list()
  logdir <- file.path(store$root, "logs"); dir.create(logdir, showWarnings = FALSE)
  start <- function(name, script, args) {
    state$specs[[name]] <- list(script = script, args = args)
    state$generations[[name]] <- brohn_default(state$generations[[name]], 0L)+1L
    prefix <- paste(name, state$session_id, state$generations[[name]], sep = "-")
    state$logs[[name]]<-list(stdout=file.path(logdir,paste0(prefix,".stdout.txt")),stderr=file.path(logdir,paste0(prefix,".stderr.txt")))
    child <- processx::process$new(brohn_rscript(), c("--vanilla", script, "--root", store$root, args),
      stdout = state$logs[[name]]$stdout, stderr = state$logs[[name]]$stderr,
      env = c("current", R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep)),
      windows_hide_window = TRUE, cleanup_tree = TRUE)
    state$started[[name]] <- as.numeric(Sys.time()); child
  }
  state$start <- start
  ok <- FALSE
  on.exit(if (!ok) {
    # A later launch can fail after the owned acquisition manager is ready.
    # Preserve its exact stop/flush/archive path before any forced fallback.
    tryCatch(brohn_stop_services(state),error=function(e)
      brohn_service_event(state,list(event="startup_cleanup_failed",message=conditionMessage(e))))
    for (child in state$owned) tryCatch({if(child$is_alive())child$kill_tree();child$wait(5000)},
      error=function(e)brohn_service_event(state,list(event="startup_cleanup_failed",message=conditionMessage(e))))
  }, add = TRUE)
  # A compatible service in this same workspace may already be running. Never
  # stop, replace or adopt an unrelated process simply because it owns the port.
  if (!brohn_participant_ready(store$workspace_id, participant_port)) {
    child <- start("participant", "scripts/run-participant.R", c("--port", as.character(participant_port)))
    state$owned$participant <- child
    .brohn_runtime_wait_ready(state,"participant",function(){ready<-brohn_participant_ready(store$workspace_id,participant_port)
      list(ready=ready,status=if(ready)"ready"else"workspace_health_unavailable",
        error=if(ready)NULL else paste("Expected workspace health on local port",participant_port,"is unavailable; the port may already be in use."))})
  }
  if (!brohn_acquisition_ready(store$root, store$workspace_id)) {
    child <- start("acquisition", "scripts/run-acquisition.R", character())
    state$owned$acquisition <- child
    .brohn_runtime_wait_ready(state,"acquisition",function()brohn_acquisition_service_status(store$root,store$workspace_id))
  }
  # Do not claim analysis work or compete with cold service initialization until
  # both workspace-owned service identities have passed their readiness checks.
  state$owned$worker <- start("worker", "scripts/run-worker.R", character())
  Sys.setenv(BROHN_PARTICIPANT_PORT = as.character(participant_port))
  state$workspace_id <- store$workspace_id; ok <- TRUE; state
}
brohn_stop_services <- function(state) {
  state$stopped <- TRUE
  # Complete the exact owned recorder's stop/flush/archive path before the
  # runtime tears down its process tree. Compatible external managers are never
  # adopted or sent stop controls by this runtime.
  acquisition <- state$owned$acquisition
  if (!is.null(acquisition) && acquisition$is_alive()) {
    requested <- tryCatch({brohn_request_acquisition_manager_stop(state$root, acquisition$get_pid()); TRUE}, error = function(e) FALSE)
    if (requested) acquisition$wait(20000)
  }
  for (child in state$owned) if (child$is_alive()) child$kill_tree()
  invisible(NULL)
}
brohn_service_event <- function(state, event) {
  record <- c(list(at = brohn_now(), runtime = state$session_id), event)
  state$events <- tail(c(state$events, list(record)), 50L)
  # Keep the diagnostic trail outside study observations and result provenance.
  tryCatch(cat(brohn_json(record), "\n", file = file.path(state$root, "logs", paste0(state$session_id, "-recovery.jsonl")), append = TRUE, sep = ""), error = function(e) NULL)
  invisible(NULL)
}
brohn_tick_services <- function(state, now = as.numeric(Sys.time())) {
  if (isTRUE(state$stopped)) return(invisible(list()))
  for (name in names(state$owned)) {
    child <- state$owned[[name]]
    if (child$is_alive()) {
      if (now-brohn_default(state$started[[name]], now) >= 30) state$failures[[name]] <- 0L
      next
    }
    if (now < brohn_default(state$next_attempt[[name]], 0)) next
    # Never replace a compatible participant service another launcher started.
    if (name == "participant" && brohn_participant_ready(state$workspace_id, state$participant_port)) {
      state$owned[[name]] <- NULL
      brohn_service_event(state, list(service = name, event = "compatible_external_service_reused")); next
    }
    if (name == "acquisition" && brohn_acquisition_ready(state$root, state$workspace_id)) {
      state$owned[[name]] <- NULL
      brohn_service_event(state, list(service = name, event = "compatible_external_service_reused")); next
    }
    failures <- brohn_default(state$failures[[name]], 0L)+1L
    state$failures[[name]] <- failures; delay <- min(60, 2^min(failures-1L, 6L))
    state$next_attempt[[name]] <- now+delay
    spec <- state$specs[[name]]
    brohn_service_event(state, list(service = name, event = "unexpected_exit", exit_code = child$get_exit_status(), retry_delay_s = delay))
    replacement <- tryCatch(state$start(name, spec$script, spec$args), error = identity)
    if (inherits(replacement, "error")) {
      state$last_error[[name]] <- substr(conditionMessage(replacement), 1, 2000)
      brohn_service_event(state, list(service = name, event = "restart_failed", message = state$last_error[[name]]))
    } else {
      state$owned[[name]] <- replacement; state$last_error[[name]] <- NULL
      brohn_service_event(state, list(service = name, event = "restart_started", generation = state$generations[[name]]))
    }
  }
  state$snapshot <- lapply(c("participant", "worker", "acquisition"), function(name) {
    child <- state$owned[[name]]
    ready <- if (name == "participant") brohn_participant_ready(state$workspace_id, state$participant_port) else
      if (name == "acquisition") brohn_acquisition_ready(state$root, state$workspace_id) else !is.null(child) && child$is_alive()
    list(service = name, ready = ready, owned = !is.null(child), generation = brohn_default(state$generations[[name]], 0L),
      status = if (ready) "available" else if (is.null(child)) "external_unavailable" else if (child$is_alive()) "starting" else "restarting",
      last_error = state$last_error[[name]])
  })
  invisible(state$snapshot)
}
brohn_monitor_services <- function(state) {
  if (isTRUE(state$scheduled) || isTRUE(state$stopped)) return(invisible(NULL))
  state$scheduled <- TRUE
  tick <- function() {
    if (isTRUE(state$stopped)) {state$scheduled <- FALSE; return(invisible(NULL))}
    tryCatch(brohn_tick_services(state), error = function(e) brohn_service_event(state, list(service = "supervisor", event = "monitor_error", message = substr(conditionMessage(e), 1, 2000))))
    later::later(tick, 2)
  }
  later::later(tick, 0)
  invisible(NULL)
}
