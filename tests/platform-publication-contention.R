source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
# Opt-in measured experiment, not a performance threshold in the ordinary suite.
# Usage: Rscript --vanilla tests/platform-publication-contention.R [64,1024] [receipt.json]
# Generates at most two original fixture files and immutable copies per size.
for (module in c("platform-core", "platform-store", "platform-delivery", "platform-vision"))
  source(paste0("R/", module, ".R"), encoding = "UTF-8")
local({
  args <- commandArgs(TRUE)
  sizes <- if (length(args)) as.numeric(strsplit(args[[1L]], ",", fixed = TRUE)[[1L]]) else c(64, 1024)
  stopifnot(length(sizes) <= 4L, all(is.finite(sizes)), all(sizes >= 1 & sizes <= 1024), !anyDuplicated(sizes))
  output <- if (length(args) > 1L) args[[2L]] else NULL
  directory <- tempfile("brohn-publication-contention-"); dir.create(directory)
  directory <- normalizePath(directory, winslash = "/")
  store <- NULL; children <- list(); checks <- 0L
  on.exit({
    for (child in children) if (child$is_alive()) child$kill_tree()
    if (!is.null(store)) brohn_close_store(store)
    actual <- normalizePath(directory, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")),
      startsWith(basename(actual), "brohn-publication-contention-"))
    Sys.chmod(list.files(actual, recursive = TRUE, full.names = TRUE, all.files = TRUE), "0666")
    unlink(actual, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  check <- function(name, ok) {if (!isTRUE(ok)) stop("Contention experiment: ", name); checks <<- checks + 1L}
  wait_files <- function(paths, seconds = 30) {
    began <- Sys.time()
    while (!all(file.exists(paths))) {
      if (as.numeric(difftime(Sys.time(), began, units = "secs")) > seconds ||
          any(vapply(children, function(p) !p$is_alive() && p$get_exit_status() != 0, logical(1)))) {
        errors <- vapply(children, function(p) paste(p$read_all_error(), collapse = " "), character(1))
        stop("Isolated fixture did not reach its barrier: ", paste(errors, collapse = " | "))
      }
      Sys.sleep(.01)
    }
  }
  event <- function(sequence) list(sequence = sequence, id = paste0("visibility-", sequence), type = "visibility",
    step_id = NULL, stimulus_id = NULL, condition_id = NULL, question_id = NULL, phase = "setup",
    clock = list(id = "browser-monotonic", unit = "ms", value = as.character(sequence),
      instance_id = "original-fixture-page", time_origin_ms = "1000000000000"), payload = list(hidden = FALSE))
  store <- brohn_open_store(file.path(directory, "workspace"))
  design <- brohn_new_design("Original publication contention fixture", id = "study-contention")
  for(i in seq_along(design$stimuli)) design$stimuli[[i]]$content <- paste("Original synthetic concept",i)
  invisible(brohn_put_entity(store, "study", design$id, design))
  deployment <- brohn_publish(store, design$id, origin = "sample", quota = 1L)
  run <- .brohn_delivery_start(store, deployment$token, list(consented = TRUE, client_id = "original-client",
    operation_id = "original-start", participant_alias = "Original synthetic participant"))
  initial <- list(events = list(event(1L)), operation_id = "initial-event")
  before <- as.numeric(Sys.time())
  receipt <- .brohn_delivery_receive(store, run$run_id, run$access_token, initial)
  baseline <- as.numeric(Sys.time()) - before
  check("uncontended event is saved", receipt$acked_sequence == 1L)
  observations <- list(); sequence <- 2L
  # Complete original NDJSON rows; data are generated locally, with no research
  # claim or external participant content. Large files never occupy an R vector.
  line <- charToRaw(paste0('{"fixture":"original-publication-load","value":0,"clock":"0.000",',
    '"note":"', paste(rep("x", 945L), collapse = ""), '"}\n'))
  block <- rep(line, max(1L, floor(1024^2 / length(line))))
  for (mib in sizes) {
    case <- file.path(store$root, "scratch", paste0("case-", mib)); dir.create(case, recursive = TRUE)
    artifacts <- file.path(case, "artifacts"); dir.create(artifacts)
    source_path <- file.path(artifacts, "original-observations.jsonl")
    con <- file(source_path, "wb")
    for (i in seq_len(ceiling(mib * 1024^2 / length(block)))) writeBin(block, con)
    close(con)
    size <- as.numeric(file.info(source_path)$size); hash <- digest::digest(file = source_path, algo = "sha256")
    job <- brohn_enqueue_job(store, "original_contention_fixture", list(origin = "sample", fixture_bytes = size), paste0("contention-", mib))
    claim <- brohn_claim_job(store, "original-contention-publisher", lease_seconds = 60)
    check("fresh exact job claimed", identical(job$id, claim$id))
    request <- list(workspace = store$root, scratch = normalizePath(case, winslash = "/"), job_id = job$id,
      report_id = paste0("report-contention-", mib), run_id = run$run_id, access_token = run$access_token,
      analysis = list(kind = "transport_fixture", artifacts = list(list(kind = "vision-observations", path = normalizePath(source_path, winslash = "/"),
        sha256 = hash, bytes = size))), event_request = list(events = list(event(sequence)), operation_id = paste0("event-", sequence)))
    for (name in c("observer_ready", "publisher_ready", "entered", "go", "observer_result", "publisher_result")) request[[name]] <- file.path(case, name)
    request_path <- file.path(case, "request.rds"); saveRDS(request, request_path)
    children <- lapply(c("observer", "publisher"), function(mode) processx::process$new(file.path(R.home("bin"), "Rscript.exe"),
      c("--vanilla", "tests/fixtures/platform-publication-contention-child.R", mode, request_path),
      env = c("current", R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep)),
      stdout = "|", stderr = "|", cleanup_tree = TRUE, windows_hide_window = TRUE))
    wait_files(c(request$observer_ready, request$publisher_ready))
    writeLines("go", request$go)
    wait_files(c(request$observer_result, request$publisher_result), seconds = 90)
    for (child in children) child$wait(2000)
    check("both isolated processes exit normally", all(vapply(children, function(p) identical(p$get_exit_status(), 0L), logical(1))))
    observer <- readRDS(request$observer_result); publisher <- readRDS(request$publisher_result)
    check("publisher succeeds through original fenced helper", identical(publisher$status, "succeeded") && brohn_get_job(store, job$id)$status == "succeeded")
    check("contention either saves or returns retryable workspace busy",observer$http_status==200L ||
      (observer$http_status==503L && identical(observer$response$error$code,"workspace_busy") && identical(observer$retry_after,"1")))
    check("receipt begins during actual writer lock", observer$started >= publisher$lock_entered && observer$started < publisher$ended)
    saved_before_retry <- brohn_run(store, run$run_id)$acked_sequence
    retry <- .brohn_delivery_receive(store, run$run_id, run$access_token, request$event_request)
    check("retry preserves exactly one event", retry$acked_sequence == sequence && length(brohn_run_events(store, run$run_id)) == sequence)
    report <- brohn_get_entity(store, "report", request$report_id)
    check("full original artifact survives immutable publication", identical(report$body$analysis$artifacts[[1L]]$hash, hash) &&
      identical(digest::digest(file = brohn_object_path(store, hash), algo = "sha256"), hash))
    observations[[length(observations) + 1L]] <- list(requested_mib = mib, artifact_bytes = size,
      publisher_seconds = publisher$elapsed_seconds, writer_lock_seconds = publisher$lock_seconds,
      participant_receipt_seconds = observer$elapsed_seconds, participant_http_status = observer$http_status,
      participant_response = observer$response, participant_retry_after = observer$retry_after, acknowledged_before_retry = saved_before_retry,
      acknowledged_after_retry = retry$acked_sequence, publication_succeeded = TRUE)
    cat(sprintf("%s MiB: writer lock %.3fs; participant receipt %.3fs, HTTP %s; exact retry saved.\n",
      mib, publisher$lock_seconds, observer$elapsed_seconds, observer$http_status))
    flush.console(); sequence <- sequence + 1L
  }
  result <- list(schema = "brohn-publication-contention-evidence/1.0", measured_at = brohn_now(),
    sqlite_busy_timeout_ms = DBI::dbGetQuery(store$con, "PRAGMA busy_timeout")[[1L]][[1L]],
    uncontended_receipt_seconds = baseline, checks = checks, observations = observations,
    source_identity = lapply(c("R/platform-store.R", "R/platform-jobs.R", "R/platform-vision.R", "R/platform-delivery.R"),
      function(path) list(path = path, sha256 = digest::digest(file = path, algo = "sha256"))),
    scope = "Unmodified artifact promotion plus current general fenced report publication sequence; actual participant app event handler; no artificial storage delay.",
    limitations = list("Local machine timing is not a performance guarantee.", "Camera, interchange and curation paths reviewed statically; their full large-file journeys are not measured here.",
      "No attempt was forced beyond the 60-second lease. The measured contention is sufficient to assess receipt blocking separately."))
  if (!is.null(output)) {
    stopifnot(!file.exists(output), dir.exists(dirname(output)))
    writeLines(brohn_json(result), output, useBytes = TRUE)
  }
  cat("Publication contention:", checks, "scoped checks passed.\n")
})
