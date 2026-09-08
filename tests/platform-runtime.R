# Isolated real-process acceptance tests. Never inspect or stop a service that
# this test did not start; every port is selected dynamically on loopback.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
if (!exists("brohn_acquisition_manager", mode = "function")) source("R/platform-acquisition.R", encoding = "UTF-8")
source("tests/fixtures/platform-analysis-fixture.R")
local({
  checks <- 0L
  check <- function(name, ok) {
    if (!isTRUE(ok)) stop(paste("Runtime QA failed:", name), call. = FALSE)
    checks <<- checks + 1L
  }
  until <- function(test, timeout = 20, tick = NULL) {
    deadline <- as.numeric(Sys.time()) + timeout
    repeat {
      if (!is.null(tick)) tick()
      if (isTRUE(test())) return(TRUE)
      if (as.numeric(Sys.time()) >= deadline) return(FALSE)
      Sys.sleep(.05)
    }
  }
  root <- tempfile("brohn-runtime-qa-"); dir.create(root)
  root <- normalizePath(root, winslash = "/")
  states <- list(); processes <- list(); stores <- list()
  previous_port <- Sys.getenv("BROHN_PARTICIPANT_PORT", unset = NA_character_)
  on.exit({
    for (state in states) try(brohn_stop_services(state), silent = TRUE)
    for (child in processes) if (child$is_alive()) child$kill_tree()
    for (store in stores) try(brohn_close_store(store), silent = TRUE)
    if (is.na(previous_port)) Sys.unsetenv("BROHN_PARTICIPANT_PORT") else Sys.setenv(BROHN_PARTICIPANT_PORT = previous_port)
    actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")),
      grepl("^brohn-runtime-qa-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  free_port <- function() httpuv::randomPort(min = 19000L, max = 49000L)
  open_store <- function(name) {
    store <- brohn_open_store(file.path(root, name)); stores[[length(stores)+1L]] <<- store; store
  }
  start_state <- function(store, port) {
    state <- brohn_start_services(store$root, port); states[[length(states)+1L]] <<- state; state
  }
  spawn_participant <- function(store, port, label) {
    child <- processx::process$new(brohn_rscript(), c("--vanilla", "scripts/run-participant.R", "--root", store$root, "--port", port),
      env = c("current", R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep)),
      stdout = file.path(root, paste0(label, ".stdout.txt")), stderr = file.path(root, paste0(label, ".stderr.txt")),
      cleanup_tree = TRUE, windows_hide_window = TRUE)
    processes[[length(processes)+1L]] <<- child
    check(paste(label, "actual participant becomes ready"), until(function() brohn_participant_ready(store$workspace_id, port)))
    child
  }
  spawn_acquisition <- function(store, label) {
    child <- processx::process$new(brohn_rscript(), c("--vanilla","scripts/run-acquisition.R","--root",store$root),
      env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),
      stdout=file.path(root,paste0(label,".stdout.txt")),stderr=file.path(root,paste0(label,".stderr.txt")),
      cleanup_tree=TRUE,windows_hide_window=TRUE)
    processes[[length(processes)+1L]] <<- child
    check(paste(label,"external acquisition manager starts"),until(function() brohn_acquisition_ready(store$root,store$workspace_id)))
    child
  }
  start_synthetic_recording <- function(store, label) {
    lsl_session<-brohn_id("synthetic");source_id<-brohn_id("source")
    config<-file.path(root,paste0(label,"-lsl.cfg"));fixture<-file.path(root,paste0(label,"-outlet.py"))
    writeLines(c("[multicast]","ResolveScope = machine","[lab]","KnownPeers = {127.0.0.1}",paste("SessionID =",lsl_session)),config)
    writeLines(c("import os,time", "import pylsl",
      "info=pylsl.StreamInfo('Brohn original runtime QA','EDA',1,50,'double64',os.environ['BROHN_QA_SOURCE'])",
      "info.desc().append_child_value('origin','synthetic')",
      "c=info.desc().append_child('channels').append_child('channel')",
      "c.append_child_value('label','original');c.append_child_value('unit','uS');c.append_child_value('type','EDA')",
      "outlet=pylsl.StreamOutlet(info,chunk_size=1,max_buffered=5)",
      "while True:","    if outlet.have_consumers(): outlet.push_sample([0.0],timestamp=pylsl.local_clock())","    time.sleep(.02)"),fixture)
    child<-processx::process$new(.brohn_acq_python(),fixture,
      env=c("current",LSLAPICFG=config,BROHN_QA_SOURCE=source_id),stdout=file.path(root,paste0(label,"-outlet.stdout")),
      stderr=file.path(root,paste0(label,"-outlet.stderr")),cleanup_tree=TRUE,windows_hide_window=TRUE)
    processes[[length(processes)+1L]] <<- child
    study<-brohn_create_study(store,paste("Original runtime recording",label))
    discovery<-brohn_queue_lsl_discovery(store,study$id,lsl_session,source_id)
    check(paste(label,"integrated manager discovers exact synthetic source"),until(function() identical(brohn_get_entity(store,"acquisition_discovery",discovery$id)$body$status,"ready")))
    discovery<-brohn_get_entity(store,"acquisition_discovery",discovery$id);observed<-discovery$body$result$streams[[1L]]
    selection<-brohn_lsl_selection(discovery,observed$uid,"eda","explicit-clock","monotonic","signal",
      list(list(id="eda",label="Original EDA",type="EDA",unit="uS",value_type="float64")),"Original synthetic runtime fixture")
    record<-brohn_queue_acquisition(store,study$id,discovery$id,list(selection),list(participant_id="explicit-P",session_id=label),"sample",
      "Original synthetic runtime fixture only.",list(max_duration_s=45,max_samples=10000,max_bytes=4*1024^2,chunk_samples=32,inlet_buffer=2),study$revision,TRUE)
    check(paste(label,"integrated manager records actual samples"),until(function() {r<-brohn_acquisition(store,record$id);!is.null(r$live_snapshot)&&r$live_snapshot$samples>=5}))
    brohn_acquisition(store,record$id)
  }
  kill_owned <- function(state, name) {
    child <- state$owned[[name]]; check(paste(name, "was alive before test crash"), child$is_alive())
    child$kill_tree(); child$wait(5000)
    check(paste(name, "test crash ends actual child"), !child$is_alive())
    child
  }

  store <- open_store("owned"); port <- free_port(); state <- start_state(store, port)
  check("startup owns participant worker and acquisition manager", setequal(names(state$owned), c("participant", "worker", "acquisition")))
  check("participant health identifies exact isolated workspace", brohn_participant_ready(store$workspace_id, port))
  check("health rejects another workspace identity", !brohn_participant_ready("other-workspace", port))
  check("initial worker stays running", until(function() state$owned$worker$is_alive()))
  check("acquisition manager readiness identifies exact workspace", brohn_acquisition_ready(store$root, store$workspace_id))
  check("acquisition readiness rejects another workspace identity", !brohn_acquisition_ready(store$root, "another-workspace"))
  old_acquisition <- kill_owned(state, "acquisition")
  brohn_tick_services(state)
  check("crashed acquisition manager receives a distinct owned replacement", state$owned$acquisition$get_pid() != old_acquisition$get_pid())
  check("replacement acquisition manager restores same workspace readiness", until(function() brohn_acquisition_ready(store$root, store$workspace_id), tick=function() brohn_tick_services(state)))

  original_worker <- kill_owned(state, "worker")
  brohn_tick_services(state)
  check("unexpected worker exit creates new owned process", state$owned$worker$get_pid() != original_worker$get_pid() && state$owned$worker$is_alive())
  check("worker restart advances generation and records exit", state$generations$worker == 2 &&
    any(vapply(state$events, function(e) identical(e$service, "worker") && identical(e$event, "unexpected_exit"), logical(1))))

  # The new controller must execute real pinned analysis, not merely be alive.
  f <- researcher_analysis_fixture()
  invisible(brohn_put_entity(store, "study", f$design$id, f$design))
  csv <- file.path(root, "synthetic-gaze.csv"); utils::write.csv(f$gaze, csv, row.names = FALSE, na = "")
  dataset <- brohn_ingest_dataset(store, csv, "Runtime restart oracle", modality = "gaze", study_id = f$design$id, origin = "sample")
  mapped <- brohn_curate_dataset(store, dataset$id, f$gaze_mapping, dataset$revision)
  job <- brohn_queue_dataset(store, mapped$id)
  check("restarted worker resolves a real queued job", until(function() brohn_get_job(store, job$id)$status %in% c("succeeded", "failed"),
    timeout = 45, tick = function() brohn_tick_services(state)))
  result <- brohn_get_job(store, job$id)
  if (!identical(result$status, "succeeded")) stop(paste("Restarted worker job:", brohn_json(result$error)))
  report <- brohn_get_entity(store, "report", result$result$report_id)
  check("recovered worker reproduces independent gaze contrast", abs(report$body$analysis$contrasts[[1]]$estimate - 10.833333333333334) < 1e-9)
  check("recovered publication keeps original source identity", identical(report$body$provenance$source$hash, mapped$body$source$hash))
  check("recovered result object verifies independently", identical(digest::digest(file = brohn_object_path(store, result$result$output_hash), algo = "sha256"), result$result$output_hash))

  crashed_recording <- start_synthetic_recording(store,"manager-crash")
  invisible(kill_owned(state,"acquisition"));brohn_tick_services(state)
  check("runtime restart preserves active recorder crash prefix",until(function() !is.null(brohn_acquisition(store,crashed_recording$id)$body$original),
    tick=function() brohn_tick_services(state)))
  recovered_recording<-brohn_acquisition(store,crashed_recording$id)
  check("active recording crash remains interrupted after supervised restart",identical(recovered_recording$body$completion_status,"interrupted") && !isTRUE(recovered_recording$body$inspection$complete))

  old_participant <- kill_owned(state, "participant")
  check("participant is unavailable after test crash", !brohn_participant_ready(store$workspace_id, port))
  brohn_tick_services(state)
  check("participant restarts with distinct process", state$owned$participant$get_pid() != old_participant$get_pid())
  check("restarted participant serves same workspace", until(function() brohn_participant_ready(store$workspace_id, port), tick = function() brohn_tick_services(state)))

  logs <- list.files(file.path(store$root, "logs"))
  expected_logs <- unlist(lapply(c("worker", "participant", "acquisition"), function(name) unlist(lapply(1:2, function(generation)
    paste0(name, "-", state$session_id, "-", generation, c(".stdout.txt", ".stderr.txt"))))))
  check("each service generation has separate stdout and stderr files", all(expected_logs %in% logs))
  recovery <- file.path(store$root, "logs", paste0(state$session_id, "-recovery.jsonl"))
  trail <- lapply(readLines(recovery, warn = FALSE), brohn_parse)
  check("recovery trail persists valid runtime-bound records", length(trail) >= 4 && all(vapply(trail, function(e) identical(e$runtime, state$session_id), logical(1))))

  # Inject a missing launcher after a real crash. Immediate first recovery is
  # followed by exponentially spaced retries, bounded at one minute.
  invisible(kill_owned(state, "worker"))
  state$specs$worker$script <- file.path(root, "intentionally-missing-worker.R")
  now <- max(as.numeric(Sys.time()), brohn_default(state$next_attempt$worker, 0)) + .01
  previous_generation <- state$generations$worker
  brohn_tick_services(state, now = now)
  check("failed child launch is isolated to worker generation", state$generations$worker == previous_generation + 1)
  check("missing launcher actually exits", until(function() !state$owned$worker$is_alive()))
  retry <- state$next_attempt$worker
  generation <- state$generations$worker
  brohn_tick_services(state, now = retry - .01)
  check("no new worker starts before backoff expires", state$generations$worker == generation)
  brohn_tick_services(state, now = retry + .01)
  check("worker retries after backoff", state$generations$worker == generation + 1)
  check("repeated crash increases retry interval", state$next_attempt$worker - (retry + .01) >= 4)
  check("participant remains usable during repeated worker faults", brohn_participant_ready(store$workspace_id, port))
  check("second failed worker exits", until(function() !state$owned$worker$is_alive()))
  state$failures$worker <- 20L; now <- state$next_attempt$worker + .01
  brohn_tick_services(state, now = now)
  check("retry interval is capped at sixty seconds", state$next_attempt$worker - now == 60)

  # Scheduled callbacks must become inert after stop, even if a restart was due.
  brohn_monitor_services(state); brohn_monitor_services(state)
  check("monitor only schedules once", isTRUE(state$scheduled))
  stopped_generation <- state$generations
  brohn_stop_services(state); later::run_now(timeoutSecs = .1)
  brohn_tick_services(state, now = as.numeric(Sys.time()) + 1000)
  check("stop terminates every owned child", all(vapply(state$owned, function(child) !child$is_alive(), logical(1))))
  check("stop blocks both scheduled and direct restart", identical(state$generations, stopped_generation) && !isTRUE(state$scheduled))
  check("stopped participant releases isolated port", !brohn_participant_ready(store$workspace_id, port))

  # Compatible service predating the runtime remains externally owned.
  external_store <- open_store("compatible"); external_port <- free_port()
  external <- spawn_participant(external_store, external_port, "compatible-external")
  external_acquisition <- spawn_acquisition(external_store,"compatible-acquisition")
  reused <- start_state(external_store, external_port)
  check("compatible external participant is never adopted", is.null(reused$owned$participant) && setequal(names(reused$owned), "worker"))
  check("compatible external acquisition manager is never adopted",is.null(reused$owned$acquisition))
  snapshot <- brohn_tick_services(reused)
  check("snapshot identifies healthy externally owned participant", isTRUE(snapshot[[1]]$ready) && !isTRUE(snapshot[[1]]$owned))
  brohn_stop_services(reused)
  check("runtime stop preserves external compatible process", external$is_alive() && brohn_participant_ready(external_store$workspace_id, external_port))
  check("runtime stop preserves external acquisition manager",external_acquisition$is_alive() && brohn_acquisition_ready(external_store$root,external_store$workspace_id))

  # A different workspace on that port is never killed to make room.
  other_store <- open_store("other-workspace")
  failure <- try(brohn_start_services(other_store$root, external_port), silent = TRUE)
  check("different-workspace port collision fails explicitly", inherits(failure, "try-error"))
  check("port collision leaves unrelated process and identity intact", external$is_alive() && brohn_participant_ready(external_store$workspace_id, external_port) &&
    !brohn_participant_ready(other_store$workspace_id, external_port))

  # Ownership is relinquished if someone deliberately starts a compatible
  # participant after the owned one died but before the next supervisor tick.
  replacement_store <- open_store("replacement"); replacement_port <- free_port()
  replacement_state <- start_state(replacement_store, replacement_port)
  invisible(kill_owned(replacement_state, "participant"))
  takeover <- spawn_participant(replacement_store, replacement_port, "takeover-external")
  invisible(kill_owned(replacement_state,"acquisition"))
  acquisition_takeover<-spawn_acquisition(replacement_store,"takeover-acquisition")
  brohn_tick_services(replacement_state)
  check("compatible replacement remains external", is.null(replacement_state$owned$participant) && takeover$is_alive())
  check("compatible replacement emits explicit ownership event", any(vapply(replacement_state$events, function(e)
    identical(e$event, "compatible_external_service_reused"), logical(1))))
  brohn_stop_services(replacement_state)
  check("stop does not kill compatible replacement", takeover$is_alive() && brohn_participant_ready(replacement_store$workspace_id, replacement_port))
  check("stop does not kill compatible acquisition replacement",is.null(replacement_state$owned$acquisition) && acquisition_takeover$is_alive())

  # Exercise the actual entry point and Shiny's event loop. A test-owned stop
  # file requests normal stopApp(), so run-brohn.R's on.exit cleanup is reached.
  launcher_store <- open_store("launcher"); launcher_port <- free_port(); researcher_port <- free_port()
  while (researcher_port == launcher_port) researcher_port <- free_port()
  stop_flag <- file.path(root, "stop-launcher"); wrapper <- file.path(root, "launcher-wrapper.R")
  writeLines(c(
    "poll_stop <- function() {",
    "  if (file.exists(Sys.getenv('BROHN_QA_STOP_FILE'))) shiny::stopApp() else later::later(poll_stop, .1)",
    "}",
    "later::later(poll_stop, .1)",
    "source('scripts/run-brohn.R', encoding='UTF-8')",
    "state <- getOption('brohn.services')",
    "cat('qa_clean_exit:', isTRUE(state$stopped) && all(vapply(state$owned, function(p) !p$is_alive(), logical(1))), '\\n')"
  ), wrapper)
  launcher <- processx::process$new(brohn_rscript(), c("--vanilla", wrapper),
    env = c("current", R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep),
      BROHN_WORKSPACE = launcher_store$root, RESEARCH_PLATFORM_PORT = as.character(researcher_port),
      BROHN_PARTICIPANT_PORT = as.character(launcher_port), BROHN_QA_STOP_FILE = stop_flag),
    stdout = file.path(root, "launcher.stdout.txt"), stderr = file.path(root, "launcher.stderr.txt"),
    cleanup_tree = TRUE, windows_hide_window = TRUE)
  processes[[length(processes)+1L]] <- launcher
  check("real launcher starts separate participant endpoint", until(function() brohn_participant_ready(launcher_store$workspace_id, launcher_port), timeout = 30))
  researcher_ready <- function() tryCatch({
    connection <- url(paste0("http://127.0.0.1:", researcher_port, "/"), "rb", method = "libcurl")
    on.exit(close(connection)); body <- rawToChar(readBin(connection, "raw", 512*1024))
    grepl("Brohn", body, fixed = TRUE) && grepl("shiny", body, fixed = TRUE)
  }, error = function(e) FALSE, warning = function(w) FALSE)
  check("real launcher serves researcher Shiny page on distinct port", until(researcher_ready, timeout = 30))
  check("actual launcher activates a worker controller", until(function() {
    logs <- list.files(file.path(launcher_store$root, "logs"), pattern = "^worker-.*stdout\\.txt$", full.names = TRUE)
    length(logs) > 0 && any(vapply(logs, function(path) any(grepl("Brohn analysis worker ready", readLines(path, warn = FALSE), fixed = TRUE)), logical(1)))
  }))
  active_recording<-start_synthetic_recording(launcher_store,"normal-shiny-stop")
  writeLines("stop", stop_flag)
  ended<-until(function() !launcher$is_alive(),timeout=30)
  if(!ended) {
    cat("Launcher stop diagnosis:\n",paste(readLines(file.path(root,"launcher.stderr.txt"),warn=FALSE),collapse="\n"),"\n")
    cat(brohn_json(brohn_acquisition(launcher_store,active_recording$id)),"\n")
    for(path in list.files(file.path(launcher_store$root,"logs"),pattern="acquisition.*stderr",full.names=TRUE)) cat(paste(readLines(path,warn=FALSE),collapse="\n"),"\n")
  }
  check("normal Shiny stop returns from actual launcher",ended)
  check("launcher exits successfully through owned child cleanup", launcher$get_exit_status() == 0 &&
    any(grepl("qa_clean_exit: TRUE", readLines(file.path(root, "launcher.stdout.txt"), warn = FALSE), fixed = TRUE)))
  check("normal launcher shutdown releases participant endpoint", !brohn_participant_ready(launcher_store$workspace_id, launcher_port))
  closed_recording<-brohn_acquisition(launcher_store,active_recording$id)
  if(is.null(closed_recording$body$original) || !identical(closed_recording$body$completion_status,"completed")) {
    cat("Recording after launcher shutdown:\n",brohn_json(closed_recording),"\n")
    service<-brohn_get_entity(launcher_store,"acquisition_service","local");cat("Manager:\n",brohn_json(service),"\n")
    for(path in list.files(file.path(launcher_store$root,"acquisitions"),pattern="stop-.*json",full.names=TRUE)) cat(paste(readLines(path,warn=FALSE),collapse="\n"),"\n")
    for(path in list.files(file.path(launcher_store$root,"logs"),pattern="acquisition.*stderr",full.names=TRUE)) cat(paste(readLines(path,warn=FALSE),collapse="\n"),"\n")
  }
  check("normal Shiny shutdown finalizes active recording and archives original",identical(closed_recording$body$completion_status,"completed") &&
    isTRUE(closed_recording$body$inspection$complete) && !is.null(closed_recording$body$original))
  source_hash<-closed_recording$body$original$hash
  rebooted<-start_state(launcher_store,launcher_port)
  check("runtime restart preserves finalized recording and does not launch duplicate",length(brohn_acquisitions(launcher_store))==1L &&
    identical(brohn_acquisition(launcher_store,active_recording$id)$body$original$hash,source_hash) &&
    identical(.brohn_acq_probe(closed_recording$body$process),"absent"))
  brohn_stop_services(rebooted)
  cat(sprintf("Platform runtime: %d actual process checks passed.\n", checks))
})
