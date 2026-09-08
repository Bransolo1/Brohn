# Real launcher acceptance: no inherited R definitions can hide service loader omissions.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
local({
  checks <- 0L
  check <- function(label, ok) {if (!isTRUE(ok)) stop("Participant launcher QA failed: ", label, call. = FALSE); checks <<- checks+1L}
  root <- tempfile("brohn-participant-protocol-"); dir.create(root)
  root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace")); child <- NULL
  on.exit({
    if (!is.null(child) && child$is_alive()) {child$kill_tree(); child$wait(5000)}
    try(brohn_close_store(store), silent = TRUE)
    actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")),
      grepl("^brohn-participant-protocol-", basename(actual)))
    Sys.chmod(list.files(actual, recursive = TRUE, full.names = TRUE, all.files = TRUE), "0666")
    unlink(actual, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  brohn_initialise_library(store)
  design <- brohn_new_design("Original separate-service scale protocol"); design$stimuli <- list()
  design$questions <- lapply(1:2, function(i) {
    q <- brohn_question(paste("Original service item", i), "rating", "end", paste0("original-question-", i))
    q$options <- lapply(1:5, function(v) list(id = paste0("choice-", v), label = as.character(v), value = v)); q
  })
  design$scales <- list(list(schema = "brohn-questionnaire-scale/1.0", id = "original-service-scale",
    label = "Original service arithmetic", version = "1.0", source = "Original two-item launcher fixture; no validation claim.", scope = "end",
    items = lapply(1:2, function(i) list(question_id = design$questions[[i]]$id, reverse = i == 2L, min = 1, max = 5)),
    scoring = list(aggregation = "sum", missing = "complete", minimum_answered = 2L, prorate = FALSE), conversion = NULL))
  source <- brohn_put_entity(store, "study", design$id, design)
  release <- brohn_publish(store, design$id, origin = "sample", quota = 10, alias_required = TRUE)
  port <- httpuv::randomPort(min = 19000L, max = 49000L)
  child <- processx::process$new(brohn_rscript(), c("--vanilla", "scripts/run-participant.R", "--root", store$root, "--port", port),
    env = c("current", R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep)),
    stdout = file.path(root, "service.stdout"), stderr = file.path(root, "service.stderr"),
    cleanup_tree = TRUE, windows_hide_window = TRUE)
  deadline <- Sys.time()+20
  while (Sys.time() < deadline && child$is_alive() && !brohn_participant_ready(store$workspace_id, port)) Sys.sleep(.05)
  check("actual fresh participant process becomes ready for this workspace", child$is_alive() && brohn_participant_ready(store$workspace_id, port))
  python <- .brohn_port_python()
  helper <- file.path(root, "request.py")
  writeLines(c("import json,sys,urllib.request,urllib.error,urllib.parse", "address,method,body=sys.argv[1:4]",
    "parsed=urllib.parse.urlsplit(address);headers={'Origin':parsed.scheme+'://'+parsed.netloc,'Content-Type':'application/json'}",
    "payload=None if body=='-' else open(body,'rb').read()",
    "request=urllib.request.Request(address,data=payload,method=method,headers=headers)",
    "try:", "    response=urllib.request.urlopen(request,timeout=10)",
    "except urllib.error.HTTPError as error:", "    response=error",
    "print(json.dumps({'status':response.status,'text':response.read().decode('utf-8')}))"), helper)
  call <- function(route, payload = NULL, method = if (is.null(payload)) "GET" else "POST") {
    body <- "-"
    if (!is.null(payload)) {body <- file.path(root, "body.json"); brohn_write_json_file(payload, body)}
    answer <- processx::run(python, c("-B", helper, paste0("http://127.0.0.1:", port, route), method, body),
      windows_hide_window = TRUE, timeout = 15000, error_on_status = TRUE)
    parsed <- brohn_parse(answer$stdout)
    list(status = parsed$status, value = tryCatch(brohn_parse(parsed$text), error = function(e) NULL), text = parsed$text)
  }
  health <- call("/api/health")
  check("HTTP health reports the exact owned workspace", health$status == 200 && identical(health$value$workspace_id, store$workspace_id))
  check("health does not match a foreign workspace", !brohn_participant_ready("another-original-workspace", port))
  entry <- call(paste0("/api/entry/", release$token))
  check("public entry reports the frozen scale release", entry$status == 200 && identical(entry$value$deployment$id, release$id))
  start_path <- paste0("/api/start/", release$token)
  request <- list(consented = FALSE, participant_alias = "ORIGINAL-P001", client_id = "original-client", operation_id = "original-start")
  denied <- call(start_path, request)
  check("invalid required consent creates no run", denied$status == 403 && length(brohn_runs(store, design$id)) == 0L)
  request$consented <- TRUE
  started <- call(start_path, request)
  check("real HTTP Start loads the registered scale validator and succeeds", started$status == 200 && brohn_text(started$value$run_id, 200))
  protocol <- started$value$protocol
  check("returned protocol preserves both original scale keys and response bounds", identical(protocol$design$scales, brohn_parse(brohn_json(design$scales))))
  check("returned frozen design hash matches independent parent-process identity", identical(protocol$design_hash, brohn_hash(design)))
  run <- brohn_run(store, started$value$run_id)
  check("receiver persists the exact returned protocol and declared participant linkage", identical(run$protocol, protocol) &&
    run$participant_alias_supplied && identical(run$participant_alias, "ORIGINAL-P001") && identical(run$origin, "sample"))
  repeated <- call(start_path, request)
  check("identical HTTP Start retry returns the same run and protocol", repeated$status == 200 && identical(repeated$value, started$value) && length(brohn_runs(store, design$id)) == 1L)
  changed <- request; changed$participant_alias <- "DIFFERENT-PERSON"
  check("same operation cannot silently change participant identity", call(start_path, changed)$status == 409 && length(brohn_runs(store, design$id)) == 1L)
  revised <- source$body; revised$title <- "Later original draft title"; revised$scales[[1]]$items[[2]]$reverse <- FALSE
  brohn_put_entity(store, "study", revised$id, revised, source$revision)
  later <- request; later$client_id <- "second-original-client"; later$operation_id <- "second-original-start"
  second <- call(start_path, later)
  check("later draft edits do not change an already released participant scale key", second$status == 200 && identical(second$value$protocol$design$scales, protocol$design$scales) &&
    identical(second$value$protocol$design_hash, protocol$design_hash))
  for (route in c("/api/studies", "/api/reports", "/api/settings", "/api/publish")) {
    response <- call(route, if (route == "/api/publish") list(study_id = design$id) else NULL)
    check(paste("participant server exposes no researcher route", route), response$status == 404)
  }
  page <- call("/participant/")
  check("the same service serves the actual participant runner", page$status == 200 && grepl('src="runner.js"', page$text, fixed = TRUE))
  child$kill_tree(); child$wait(5000)
  saved <- brohn_run(store, started$value$run_id); brohn_close_store(store); store <- brohn_open_store(file.path(root, "workspace"))
  check("protocol and frozen scale keys reopen after the actual service exits", identical(brohn_run(store, started$value$run_id), saved))
  cat(sprintf("PASS: %d actual separate participant-service protocol assertions\n", checks))
})
