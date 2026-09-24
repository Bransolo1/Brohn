# Actual receiver fixture with an explicitly synthetic trusted-edge adapter.
# It does not qualify TLS, OIDC, physical devices, or scientific worker outputs.
args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) { i <- match(name, args); if (is.na(i)) default else args[[i + 1L]] }
mode <- args[[1L]]
folder <- normalizePath(arg("--folder"), winslash = "/", mustWork = TRUE)
stopifnot(startsWith(basename(folder), "brohn-runtime-browser-"))
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
root <- file.path(folder, if (identical(arg("--restored"), "yes")) "restored" else "workspace")
store <- brohn_open_store(root)
local({
  on.exit(brohn_close_store(store), add = TRUE)
  config_path <- file.path(folder, "fixture.json")
  profile_path <- file.path(folder, "profile.json")
  researcher <- function() {
    p <- brohn_validate_hosted_profile(brohn_read_json_file(profile_path))
    ctx <- brohn_hosted_context(list(HTTP_HOST = "localhost:3991", HTTP_X_FORWARDED_PROTO = "https",
      HTTP_X_BROHN_EDGE = p$edge_secret, HTTP_X_FORWARDED_USER = "original-runtime-fixture-researcher",
      HTTP_X_FORWARDED_GROUPS = "researchers"), p)
    brohn_hosted_bind_store(store, p, ctx)
  }
  if (mode == "prepare") {
    stopifnot(!file.exists(config_path), "participant_static_root" %in% names(formals(brohn_publish)))
    brohn_initialise_library(store)
    site <- file.path(folder, "site"); dir.create(site)
    dir.create(file.path(site, "participant")); dir.create(file.path(site, "brand"))
    paths <- .brohn_runner_paths()
    for (path in paths) stopifnot(file.copy(file.path("www", path), file.path(site, path)))
    expected_a <- setNames(lapply(paths, function(path) digest::digest(file = file.path(site, path), algo = "sha256")), paths)
    secret <- file.path(folder, "edge.secret"); writeChar(brohn_token(), secret, eos = NULL, useBytes = TRUE)
    revocations <- file.path(folder, "revocations.json")
    brohn_write_json_file(list(schema = "brohn-hosted-revocations/1.0", subjects = list(), not_before = 0), revocations)
    p <- list(schema = "brohn-hosted-profile/1.0", id = "original-runtime-browser", mode = "local_oidc_fixture",
      workspace_root = store$root, workspace_id = store$workspace_id, project_id = "default",
      researcher_origin = "https://localhost:3991", participant_origin = "https://localhost:3992",
      issuer = "http://127.0.0.1:3993/realms/brohn", allowed_groups = list("researchers"),
      edge_secret_file = secret, revocations_file = revocations, session_seconds = 3600L,
      enrollment_seconds = 3600L, upload_seconds = 7200L, resource_seconds = 7200L,
      researcher_port = 3994L, participant_port = 3995L, oauth_port = 3996L)
    brohn_write_json_file(p, profile_path); bound <- researcher()
    design <- brohn_new_design("Original runtime recovery survey", "survey", "study-runtime-browser")
    # No timed/device method is requested in this original text-only fixture.
    design$participant_equipment <- NULL
    design$questions <- list(brohn_question("Describe the original concept", "text", "end", "q-original-runtime"))
    design$instructions <- "Read these original survey instructions, then continue."
    brohn_put_entity(bound, "study", design$id, design)
    labels <- c("committed_revoked", "uncommitted_revoked", "committed_expired", "run_revoked", "run_expired")
    releases <- setNames(lapply(labels, function(label) brohn_publish(bound, design$id, origin = "sample", quota = 3L,
      participant_static_root = file.path(site, "participant"))), labels)
    # This only changes the external copied distribution, after original releases.
    for (name in c("runner.js", "audio-worklet.js")) {
      file <- file.path(site, "participant", name)
      bytes <- readBin(file, "raw", n = file.info(file)$size)
      writeBin(c(bytes, charToRaw("\n// Original fixture distribution B; scientific behavior unchanged.\n")), file)
    }
    releases$newer <- brohn_publish(bound, design$id, origin = "sample", quota = 2L,
      participant_static_root = file.path(site, "participant"))
    # Explicit simulation of pre-feature metadata, not a historical execution claim.
    releases$legacy <- .brohn_publish_release(bound, design$id, origin = "sample", quota = 2L)
    expected_b <- setNames(lapply(paths, function(path) digest::digest(file = file.path(site, path), algo = "sha256")), paths)
    runtimes <- lapply(releases, function(release) brohn_runner_assets_read(store, release$id))
    brohn_write_json_file(list(releases = releases, runtimes = runtimes, expected_a = expected_a, expected_b = expected_b,
      design_hash = brohn_hash(design), scope = "original text survey; synthetic trusted-edge HTTP adapter"), config_path)
  } else if (mode == "serve") {
    port <- as.integer(arg("--port")); stop_name <- arg("--stop", "stop.1")
    stopifnot(grepl("^stop[.][0-9]+$", stop_name), is.finite(port), port > 1024L)
    static <- file.path(folder, if (identical(arg("--absent"), "yes")) "absent-site/participant" else "site/participant")
    if (identical(arg("--absent"), "yes")) stopifnot(!dir.exists(static))
    if (!identical(arg("--restored"), "yes")) {
      p <- brohn_validate_hosted_profile(brohn_read_json_file(profile_path))
      bound <- brohn_hosted_bind_store(store, p, participant = TRUE)
      app <- brohn_delivery_app(bound, static_root = static)
      handler <- list(call = function(req) {
        if (req$PATH_INFO %in% c("/participant", "/participant/"))
          cat("ENTRY QUERY PREFIX:", substr(req$QUERY_STRING, 1L, 1L), "\n")
        # Explicitly simulate verified edge transport for these isolated policy tests.
        # Browser -> R HTTP remains real; this is not a public TLS/OIDC acceptance.
        req$HTTP_HOST <- "localhost:3992"; req$HTTP_X_FORWARDED_PROTO <- "https"
        req$HTTP_X_BROHN_EDGE <- p$edge_secret
        if (!is.null(req$HTTP_ORIGIN)) req$HTTP_ORIGIN <- p$participant_origin
        result <- app$call(req)
        if (endsWith(req$PATH_INFO, "/participant/audio-worklet.js")) {
          receipt <- list(path = req$PATH_INFO, status = result$status,
            hash = if (is.raw(result$body)) digest::digest(result$body, algo = "sha256", serialize = FALSE) else NULL)
          cat(.brohn_store_json(receipt), "\n", file = file.path(folder, "worklet-responses.jsonl"), append = TRUE)
        }
        result
      })
    } else handler <- brohn_delivery_app(store, static_root = static)
    server <- httpuv::startServer("127.0.0.1", port, handler)
    on.exit(httpuv::stopServer(server), add = TRUE)
    while (!file.exists(file.path(folder, stop_name))) httpuv::service(50)
  } else if (mode == "policy") {
    config <- brohn_read_json_file(config_path); release <- config$releases[[arg("--case")]]
    stopifnot(!is.null(release)); policy <- arg("--policy"); now <- as.numeric(Sys.time())
    if (policy == "release_revoked") brohn_hosted_revoke(researcher(), "release", release$id)
    else if (policy == "release_expired") DBI::dbExecute(store$con,
      "UPDATE hosted_release_policy SET enrollment_expires=?,resource_expires=? WHERE deployment_id=?",
      params = list(now - 1, now - 1, release$id))
    else {
      run <- DBI::dbGetQuery(store$con, "SELECT id FROM delivery_runs WHERE deployment_id=?", params = list(release$id))
      stopifnot(nrow(run) == 1L)
      if (policy == "run_revoked") brohn_hosted_revoke(researcher(), "run", run$id[[1L]])
      else if (policy == "run_expired") DBI::dbExecute(store$con,
        "UPDATE hosted_run_policy SET upload_expires=? WHERE run_id=?", params = list(now - 1, run$id[[1L]]))
      else stop("Unknown fixture policy.")
    }
  } else if (mode %in% c("inspect", "cancel")) {
    if (mode == "cancel") for (job in brohn_list_jobs(store, limit = 100L))
      if (job$status == "queued") brohn_cancel_job(store, job$id)
    runs <- lapply(brohn_runs(store), function(run) list(run = run, events = brohn_run_events(store, run$id),
      assignment = brohn_rows(DBI::dbGetQuery(store$con, "SELECT * FROM delivery_run_runtimes WHERE run_id=?", params = list(run$id))),
      jobs = lapply(brohn_list_jobs(store, 100L, list(run_id = run$id)), function(job) job[c("id", "operation", "status", "attempt")])) )
    brohn_write_json_file(list(runs = runs, runtimes = brohn_rows(DBI::dbGetQuery(store$con, "SELECT deployment_id,manifest_hash FROM delivery_runtimes")),
      receipts = brohn_rows(DBI::dbGetQuery(store$con, "SELECT scope,operation,operation_id,request_hash FROM delivery_receipts")),
      paused = brohn_workspace_execution_status(store)$paused), file.path(folder, if (identical(arg("--restored"), "yes")) "restored-inspection.json" else "inspection.json"))
  } else if (mode == "backup") {
    backup <- brohn_backup_workspace(store, file.path(folder, "backup"))
    brohn_restore_workspace(backup$path, file.path(folder, "restored"))
    restored <- brohn_open_store(file.path(folder, "restored")); on.exit(brohn_close_store(restored), add = TRUE)
    releases <- brohn_deployments(restored)
    brohn_write_json_file(list(releases = releases, paused = brohn_workspace_execution_status(restored)$paused,
      workspace_id = restored$workspace_id, original_workspace_id = store$workspace_id), file.path(folder, "restored.json"))
  } else stop("Unknown runtime browser fixture mode.")
})
