# Actual Windows entry-point checks from outside the project and with paths
# containing spaces. No cameras, participants or outlets are opened.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
local({
  if (.Platform$OS.type != "windows") stop("This acceptance script targets the Windows PowerShell launcher.")
  arguments <- commandArgs(trailingOnly = TRUE)
  if (length(arguments) != 1L) stop("Provide the explicitly restored R library directory.")
  library <- normalizePath(arguments[[1L]], winslash = "/", mustWork = TRUE)
  repo <- normalizePath(".", winslash = "/", mustWork = TRUE)
  root <- tempfile("brohn launcher qa "); dir.create(root)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  ps <- unname(Sys.which("powershell")); stopifnot(nzchar(ps))
  launcher <- file.path(repo, "run-local.ps1"); children <- list(); checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("Launcher QA failed: ", name); checks <<- checks+1L}
  on.exit(for (child in children) if (child$is_alive()) child$kill_tree(), add = TRUE)
  until <- function(test, seconds = 35) {
    deadline <- as.numeric(Sys.time())+seconds
    repeat {if (isTRUE(test())) return(TRUE); if (as.numeric(Sys.time()) > deadline) return(FALSE); Sys.sleep(.1)}
  }
  base <- c("-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", launcher,
    "-RscriptPath", brohn_rscript(), "-LibraryPath", library)
  ports <- unique(replicate(6L, httpuv::randomPort(min = 20000L, max = 48000L))); stopifnot(length(ports) >= 4L)
  run <- function(extra, label) {
    child <- processx::process$new(ps, c(base, extra), wd = root, env = c("current", LC_ALL = "C", RESEARCH_PLATFORM_DATA = file.path(root, "legacy-drafts")),
      stdout = file.path(root, paste0(label, ".out")), stderr = file.path(root, paste0(label, ".err")),
      cleanup_tree = TRUE, windows_hide_window = TRUE)
    children[[length(children)+1L]] <<- child; child
  }
  read_page <- function(port) tryCatch({
    connection <- url(paste0("http://127.0.0.1:", port, "/"), open = "rb", method = "libcurl")
    on.exit(close(connection)); rawToChar(readBin(connection, "raw", 512*1024))
  }, error = function(e) "", warning = function(w) "")
  # Relative workspace resolution must be against the invoking directory, not
  # the repo's directory after the PowerShell launcher changes location.
  workspace_name <- "original research workspace"
  active <- run(c("-Port", ports[[1L]], "-ParticipantPort", ports[[2L]], "-Workspace", workspace_name), "connected")
  check("default PowerShell launch serves the connected researcher shell", until(function() grepl('id="platform_status"', read_page(ports[[1L]]), fixed = TRUE)))
  workspace <- file.path(root, workspace_name)
  check("relative workspace with spaces is created under the caller directory", file.exists(file.path(workspace, "catalog.sqlite")))
  store <- brohn_open_store(workspace); id <- store$workspace_id; brohn_close_store(store)
  check("separate participant service answers for the selected workspace", until(function() brohn_participant_ready(id, ports[[2L]])))
  check("local acquisition manager starts without initiating discovery or recording", until(function() brohn_acquisition_ready(workspace, id)))
  store <- brohn_open_store(workspace)
  check("startup creates no study runs or acquisition requests", length(brohn_runs(store)) == 0L && length(brohn_acquisitions(store)) == 0L)
  brohn_close_store(store)
  active$kill_tree(); active$wait(10000)
  check("stopping only the test-owned launcher removes its participant process", until(function() !brohn_participant_ready(id, ports[[2L]]), 10))
  legacy <- run(c("-Legacy", "-Port", ports[[3L]], "-ParticipantPort", ports[[4L]]), "legacy")
  check("explicit legacy mode serves the retained prototype", until(function() {html <- read_page(ports[[3L]]); grepl("Brohn", html, fixed = TRUE) && !grepl('id="platform_status"', html, fixed = TRUE)}))
  check("legacy mode does not start a participant service", !brohn_participant_ready(id, ports[[4L]]))
  legacy$kill_tree(); legacy$wait(10000)
  same <- run(c("-Port", ports[[1L]], "-ParticipantPort", ports[[1L]]), "same-ports")
  same$wait(10000)
  check("equal ports fail before services start", !same$is_alive() && same$get_exit_status() != 0 &&
    any(grepl("ports must differ", readLines(file.path(root, "same-ports.err")), fixed = TRUE)))
  # Invalid selections must not silently fall back to the development library.
  invalid_args <- base; invalid_args[[length(invalid_args)]] <- file.path(root, "missing library")
  invalid <- processx::run(ps, invalid_args, wd = root,
    error_on_status = FALSE, timeout = 10000, windows_hide_window = TRUE)
  check("an explicitly missing library is refused", invalid$status != 0L && grepl("selected R library directory does not exist", invalid$stderr, fixed = TRUE))
  cat(sprintf("PASS: %d actual Windows launcher/profile checks using %s\n", checks, library))
})
