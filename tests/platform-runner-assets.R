# Exact released source preservation; no claim that stored bytes prove execution.
source("R/platform-load.R"); brohn_load(ui = FALSE)
source("R/platform-runner-assets.R")
local({
  directory <- tempfile("brohn-runner-assets-"); dir.create(directory)
  cleanup_root <- normalizePath(directory, winslash = "/", mustWork = TRUE)
  store <- brohn_open_store(file.path(directory, "workspace")); restored <- NULL
  on.exit({
    brohn_close_store(store); brohn_close_store(restored)
    stopifnot(identical(normalizePath(directory, winslash = "/"), cleanup_root),
      startsWith(cleanup_root, paste0(normalizePath(tempdir(), winslash = "/"), "/")))
    Sys.chmod(list.files(directory, recursive = TRUE, full.names = TRUE, all.files = TRUE), "0666")
    unlink(directory, recursive = TRUE)
  }, add = TRUE)
  checks <- character()
  check <- function(name, value) { if (!isTRUE(value)) stop("FAIL: ", name); checks <<- c(checks, name) }
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  site <- file.path(directory, "site"); dir.create(site)
  dir.create(file.path(site, "participant")); dir.create(file.path(site, "brand"))
  for (path in .brohn_runner_paths()) stopifnot(file.copy(file.path("www", path), file.path(site, path)))
  static <- file.path(site, "participant")
  prepared <- brohn_runner_assets_prepare(static)
  check("all actual entry assets, GNAT renderer and camera worklet retained", length(prepared$manifest$files) == 19L &&
    all(c("participant/gnat-core.js", "participant/gnat.js", "participant/audio-worklet.js",
      "brand/brohn-app-icon.svg") %in% names(prepared$bytes)))
  check("independent per-file digest matches actual source", all(vapply(prepared$manifest$files, function(item)
    identical(digest::digest(file = file.path(site, item$path), algo = "sha256"), item$hash), logical(1))))
  check("stable repeated snapshot", identical(prepared, brohn_runner_assets_prepare(static)))
  design <- brohn_new_design("Runner preservation fixture", id = "study-runner-assets")
  design$stimuli[[1L]]$content <- "Control concept"; design$stimuli[[2L]]$content <- "Candidate concept"
  brohn_put_entity(store, "study", design$id, design)
  # Explicit old publication body models a pre-feature catalog; never use it
  # from the product to bypass preserving new releases.
  legacy_empty <- .brohn_publish_release(store, design$id, origin = "sample")
  before_tables <- DBI::dbListTables(store$con)
  check("historical releases do not invent code identity", identical(brohn_runner_assets_read(store, legacy_empty$id)$status, "legacy_unpinned"))
  check("legacy runtime read does not migrate or write the catalog", identical(DBI::dbListTables(store$con), before_tables) &&
    !"delivery_runtimes" %in% before_tables)
  publish <- function() .brohn_publish_release(store, design$id, origin = "sample")
  release <- brohn_runner_assets_publish(store, prepared, publish)
  check("unknown release cannot be pinned", rejects(brohn_runner_assets_publish(store, prepared, function() list(id="release-missing"))))
  check("empty historical release cannot be pinned", rejects(brohn_runner_assets_publish(store, prepared, function() legacy_empty)))
  pinned <- release$participant_runtime
  check("pin stores exact immutable inventory", identical(pinned$manifest_hash, prepared$hash) &&
    identical(brohn_json(pinned$manifest), brohn_json(prepared$manifest)))
  check("every stored file matches source bytes", all(vapply(names(prepared$bytes), function(path)
    identical(brohn_runner_asset(store, release$id, prepared$hash, path)$body, prepared$bytes[[path]]), logical(1))))
  check("existing release cannot be republished as new", rejects(brohn_runner_assets_publish(store, prepared, function() release)))
  changed <- prepared; changed$bytes[["participant/runner.js"]][1L] <- as.raw(0)
  check("tampered prepared bytes rejected", rejects(brohn_runner_assets_publish(store, changed, publish)))
  changed <- prepared; changed$hash <- strrep("a", 64L)
  check("tampered prepared manifest rejected", rejects(brohn_runner_assets_publish(store, changed, publish)))
  check("unknown resource and traversal refused", all(vapply(c("participant/missing.js", "participant/../runner.js", "../catalog.sqlite",
    "participant/%2e%2e/runner.js", "participant/runner.js?x"), function(path)
    rejects(brohn_runner_asset(store, release$id, prepared$hash, path)), logical(1))))
  check("different manifest identity refused", rejects(brohn_runner_asset(store, release$id, strrep("a", 64), "participant/runner.js")))
  check("SQL update cannot rewrite preserved runtime", rejects(DBI::dbExecute(store$con,
    "UPDATE delivery_runtimes SET manifest_hash=? WHERE deployment_id=?", params = list(strrep("a", 64), release$id))))
  check("SQL delete cannot erase preserved runtime", rejects(DBI::dbExecute(store$con,
    "DELETE FROM delivery_runtimes WHERE deployment_id=?", params = list(release$id))))
  runner <- file.path(static, "runner.js")
  writeBin(c(prepared$bytes[["participant/runner.js"]], charToRaw("\n// Different distribution for future release.\n")), runner)
  newer <- brohn_runner_assets_prepare(static)
  check("changed distribution produces a different identity", !identical(newer$hash, prepared$hash))
  check("current installation cannot alter old release bytes", identical(brohn_runner_asset(store, release$id,
    prepared$hash, "participant/runner.js")$body, prepared$bytes[["participant/runner.js"]]))
  check("old release cannot be rebound", rejects(brohn_runner_assets_publish(store, newer, function() release)))
  release_two <- brohn_runner_assets_publish(store, newer, publish)
  check("new release retains its own changed code", identical(brohn_runner_asset(store, release_two$id,
    newer$hash, "participant/runner.js")$body, newer$bytes[["participant/runner.js"]]))
  start <- .brohn_delivery_start(store, release$token, list(consented = TRUE, client_id = "runtime-client", operation_id = "runtime-start"))
  protocol_hash <- brohn_hash(brohn_run(store, start$run_id)$protocol)
  check("run assignment rejects another runtime", rejects(brohn_runner_bind_run(store, start$run_id, newer$hash)))
  brohn_runner_bind_run(store, start$run_id, prepared$hash)
  check("run assignment and retry retain exact hash", identical(brohn_runner_bind_run(store, start$run_id, prepared$hash), prepared$hash))
  check("code assignment does not rewrite scientific protocol", identical(brohn_hash(brohn_run(store, start$run_id)$protocol), protocol_hash))
  check("SQL cannot rewrite assigned code", rejects(DBI::dbExecute(store$con, "UPDATE delivery_run_runtimes SET manifest_hash=? WHERE run_id=?",
    params = list(newer$hash, start$run_id))))
  legacy <- .brohn_publish_release(store, design$id, origin = "sample")
  .brohn_delivery_start(store, legacy$token, list(consented = TRUE, client_id = "legacy-client", operation_id = "legacy-start"))
  check("existing session refuses retrospective release pin", rejects(brohn_runner_assets_publish(store, prepared, function() legacy)) &&
    identical(brohn_runner_assets_read(store, legacy$id)$status, "legacy_unpinned"))
  atomic <- NULL
  check("outer transaction rolls back code assignment", rejects(.brohn_store_tx(store, function() {
    atomic <<- brohn_runner_assets_publish(store, newer, publish); stop("intentional transaction rollback")
  })) && is.null(brohn_deployment(store, atomic$id)))
  publication_counts <- function() setNames(vapply(c("delivery_deployments", "delivery_deployment_credentials", "delivery_runtimes", "audit_log"),
    function(table) DBI::dbGetQuery(store$con, paste("SELECT count(*) AS n FROM", table))$n[[1L]], numeric(1)),
    c("releases", "credentials", "runtimes", "audit"))
  before <- publication_counts()
  check("failed release callback rolls back release credentials and audit", rejects(brohn_runner_assets_publish(store, newer, function() {
    publish(); stop("intentional creation failure")
  })) && identical(publication_counts(), before))
  original_store_object <- brohn_store_object; fail_count <- 0L
  assign("brohn_store_object", function(...) {
    fail_count <<- fail_count + 1L
    if (fail_count == 3L) stop("intentional asset publication failure")
    original_store_object(...)
  }, envir = .GlobalEnv)
  failed <- tryCatch(rejects(brohn_runner_assets_publish(store, newer, publish)),
    finally = assign("brohn_store_object", original_store_object, envir = .GlobalEnv))
  check("failed asset storage rolls back release credentials runtime and audit", failed && fail_count == 3L &&
    identical(publication_counts(), before))
  index <- file.path(static, "index.html"); original_index <- readBin(index, "raw", n = file.info(index)$size)
  writeBin(c(original_index, charToRaw('<script src="unregistered.js"></script>')), index)
  check("new HTML dependency requires registration", rejects(brohn_runner_assets_prepare(static)))
  writeBin(original_index, index)
  worklet <- file.path(static, "audio-worklet.js"); original_worklet <- readBin(worklet, "raw", n = file.info(worklet)$size)
  unlink(worklet)
  check("missing worklet fails snapshot", rejects(brohn_runner_assets_prepare(static)))
  writeBin(original_worklet, worklet)
  writeBin(raw(1024^2 + 1L), worklet)
  check("overlarge asset fails snapshot", rejects(brohn_runner_assets_prepare(static)))
  writeBin(original_worklet, worklet)
  backup <- file.path(directory, "checkpoint.brohn-backup")
  brohn_backup_workspace(store, backup)
  brohn_restore_workspace(backup, file.path(directory, "restored"))
  restored <- brohn_open_store(file.path(directory, "restored"))
  check("backup and restore preserve original manifest", identical(brohn_runner_assets_read(restored, release$id), pinned))
  check("backup and restore preserve all runtime bytes", all(vapply(names(prepared$bytes), function(path)
    identical(brohn_runner_asset(restored, release$id, prepared$hash, path)$body, prepared$bytes[[path]]), logical(1))))
  check("restored session preserves separate assignment", identical(DBI::dbGetQuery(restored$con,
    "SELECT manifest_hash FROM delivery_run_runtimes WHERE run_id=?", params = list(start$run_id))$manifest_hash[[1L]], prepared$hash))
  check("restore retains legacy unknown identity", identical(brohn_runner_assets_read(restored, legacy$id)$status, "legacy_unpinned"))
  check("runtime catalog independently validates complete references", brohn_runner_catalog_integrity(store$con))
  corrupt <- function(mutate) {
    refused <- FALSE
    try(.brohn_store_tx(store, function() {
      mutate()
      refused <<- rejects(brohn_runner_catalog_integrity(store$con))
      stop("intentional corruption-test rollback")
    }), silent = TRUE)
    refused
  }
  check("catalog rejects rewritten manifest hash", corrupt(function() {
    DBI::dbExecute(store$con, "DROP TRIGGER delivery_runtime_no_update")
    DBI::dbExecute(store$con, "UPDATE delivery_runtimes SET manifest_hash=? WHERE deployment_id=?", params = list(strrep("a",64), release$id))
  }))
  check("catalog rejects internally rehashed missing object", corrupt(function() {
    DBI::dbExecute(store$con, "DROP TRIGGER delivery_runtime_no_update")
    manifest <- prepared$manifest; manifest$files[[1L]]$hash <- strrep("a",64)
    DBI::dbExecute(store$con, "UPDATE delivery_runtimes SET manifest_json=?,manifest_hash=? WHERE deployment_id=?",
      params = list(.brohn_store_json(manifest), brohn_hash(manifest), release$id))
  }))
  check("catalog rejects another release's runtime assignment", corrupt(function() {
    DBI::dbExecute(store$con, "DROP TRIGGER delivery_run_runtime_no_update")
    DBI::dbExecute(store$con, "UPDATE delivery_run_runtimes SET deployment_id=?,manifest_hash=? WHERE run_id=?",
      params = list(release_two$id, newer$hash, start$run_id))
  }))
  check("catalog rejects missing assigned runtime", corrupt(function() {
    DBI::dbExecute(store$con, "DROP TRIGGER delivery_run_runtime_no_delete")
    DBI::dbExecute(store$con, "DELETE FROM delivery_run_runtimes WHERE run_id=?", params = list(start$run_id))
  }))
  check("catalog rejects wrong assignment hash", corrupt(function() {
    DBI::dbExecute(store$con, "DROP TRIGGER delivery_run_runtime_no_update")
    DBI::dbExecute(store$con, "UPDATE delivery_run_runtimes SET manifest_hash=? WHERE run_id=?", params = list(newer$hash, start$run_id))
  }))
  check("zero-participant pinned release cannot become legacy after manifest loss", corrupt(function() {
    DBI::dbExecute(store$con, "DROP TRIGGER delivery_runtime_no_delete")
    DBI::dbExecute(store$con, "DELETE FROM delivery_runtimes WHERE deployment_id=?", params = list(release_two$id))
    stopifnot(rejects(brohn_runner_assets_read(store, release_two$id)))
  }))
  check("lost runtime tables cannot downgrade known preserved history", corrupt(function() {
    DBI::dbExecute(store$con, "DROP TABLE delivery_run_runtimes")
    DBI::dbExecute(store$con, "DROP TRIGGER delivery_runtime_no_delete")
    DBI::dbExecute(store$con, "DROP TABLE delivery_runtimes")
    stopifnot(rejects(brohn_runner_assets_read(store, release$id)))
  }))
  check("corruption probes preserve original catalog", brohn_runner_catalog_integrity(store$con))
  route <- function(path, query = "", target = store) brohn_runner_route(target,
    list(PATH_INFO = path, QUERY_STRING = query, REQUEST_METHOD = "GET"))
  redirect <- route("/participant/", paste0("token=", release$token))
  prefix <- paste0("/api/runtime/", release$token, "/", prepared$hash, "/")
  check("normal participant link redirects to its exact code", redirect$status == 302L &&
    identical(redirect$headers[["Location"]], paste0(prefix, "participant/index.html?token=", release$token)))
  check("slashless and historical study alias resolve identically", identical(route("/participant", paste0("study=", release$token)), redirect))
  check("httpuv leading query delimiter resolves the same exact release", identical(route("/participant/", paste0("?token=", release$token)), redirect) &&
    identical(route("/participant", paste0("?study=", release$token)), redirect))
  check("generic and historical unpinned entry keep legacy route", is.null(route("/participant/")) &&
    is.null(route("/participant/", paste0("token=", legacy$token))))
  check("pinned entry returns preserved exact HTML", identical(route(paste0(prefix, "participant/index.html"), paste0("token=", release$token))$body,
    prepared$bytes[["participant/index.html"]]))
  check("httpuv query delimiter preserves entry identity and duplicate rejection", identical(route(paste0(prefix, "participant/index.html"), paste0("?token=", release$token))$body,
    prepared$bytes[["participant/index.html"]]) && rejects(route(paste0(prefix, "participant/index.html"), paste0("?token=", release$token, "&study=", release$token))))
  check("entry refuses conflicting missing or repeated identity", all(vapply(c("", paste0("token=", release_two$token),
    paste0("token=", release$token, "&token=", release$token), paste0("token=", release$token, "&study=", release$token)),
    function(query) rejects(route(paste0(prefix, "participant/index.html"), query)), logical(1))))
  check("relative worklet and icon use preserved directory layout", identical(route(paste0(prefix, "participant/audio-worklet.js"))$body,
    prepared$bytes[["participant/audio-worklet.js"]]) && identical(route(paste0(prefix, "brand/brohn-app-icon.svg"))$body,
    prepared$bytes[["brand/brohn-app-icon.svg"]]))
  check("route cannot substitute another release manifest", rejects(route(paste0("/api/runtime/", release$token, "/", newer$hash, "/participant/runner.js"))))
  check("old restored capability cannot recover code", rejects(route(paste0(prefix, "participant/runner.js"), target = restored)))
  restored_release <- brohn_deployment(restored, release$id)
  restored_path <- paste0("/api/runtime/", restored_release$token, "/", prepared$hash, "/participant/runner.js")
  check("rotated restored capability preserves code while workspace paused", identical(route(restored_path, target = restored)$body,
    prepared$bytes[["participant/runner.js"]]) && .brohn_store_execution_paused(restored))
  brohn_deployment_state(store, release$id, "closed")
  check("closed recruitment retains code for independently authorized recovery", identical(route(paste0(prefix, "participant/runner.js"))$body,
    prepared$bytes[["participant/runner.js"]]))
  asset <- prepared$manifest$files[[which(vapply(prepared$manifest$files, function(x) x$path == "participant/runner.js", logical(1)))]]
  object <- brohn_object_path(store, asset$hash)
  Sys.chmod(object, "0666"); writeBin(charToRaw("corrupt runtime"), object)
  check("corrupt content never falls back to current installation", rejects(brohn_runner_asset(store, release$id, prepared$hash, "participant/runner.js")))
  cat(sprintf("PASS: %d participant runtime preservation checks\n", length(checks)))
  receipt <- Sys.getenv("BROHN_TEST_RECEIPT", "")
  if (nzchar(receipt)) writeLines(brohn_json(list(schema = "brohn-runner-assets-tests/1.0", passed = length(checks),
    checks = as.list(checks), runtime_hash = prepared$hash, source_hash = digest::digest(file = "R/platform-runner-assets.R", algo = "sha256"))), receipt)
})
