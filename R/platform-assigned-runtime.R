# Prospective assigned runtime profile. Legacy manifest validation is not edited.
.brohn_assigned_runtime_profile <- "brohn-assigned-runtime/0.1"
.brohn_assigned_runtime_renderer <- "brohn-assigned-host/0.1.0"
.brohn_assigned_runtime_manifest <- function(manifest, expected_hash = NULL) {
  brohn_fields(manifest, c("schema", "renderer_id", "files"), label = "Assigned participant runtime")
  .brohn_runner_require(identical(manifest$schema, .brohn_assigned_runtime_profile) &&
    identical(manifest$renderer_id, .brohn_assigned_runtime_renderer), "Unsupported assigned participant runtime profile.")
  distribution <- .brohn_assigned_runtime_distribution()
  paths <- vapply(distribution$files, `[[`, character(1), "path")
  .brohn_runner_require(is.list(manifest$files) && length(manifest$files) == 33L,
    "The assigned runtime must preserve its complete closed 33-file distribution.")
  for (i in seq_along(paths)) {
    item <- manifest$files[[i]]
    brohn_fields(item, c("path", "hash", "size", "media_type"), label = "Assigned participant runtime file")
    registered <- distribution$files[[i]]
    .brohn_runner_require(identical(item$path, paths[[i]]) &&
      brohn_text(item$hash, 64L) && grepl("^[a-f0-9]{64}$", item$hash) &&
      brohn_number(item$size, 1, 1024^2, TRUE) &&
      identical(item$hash, registered$hash) && item$size == registered$size &&
      identical(item$media_type, registered$media_type), "The assigned runtime differs from its registered application distribution.")
  }
  .brohn_runner_require(sum(vapply(manifest$files, `[[`, numeric(1), "size")) <= 8 * 1024^2,
    "The complete assigned runtime exceeds 8 MiB.")
  hash <- brohn_hash(manifest)
  if (!is.null(expected_hash)) .brohn_runner_require(identical(hash, expected_hash), "The saved assigned runtime manifest changed.")
  invisible(hash)
}

brohn_assigned_runtime_prepare <- function(static_root) {
  .brohn_runner_require(brohn_text(static_root, 4096L) && dir.exists(static_root), "The assigned study player is unavailable.", 503L)
  root <- normalizePath(static_root, winslash = "/", mustWork = TRUE)
  expected <- .brohn_assigned_runtime_distribution()
  .brohn_assigned_runtime_manifest(expected)
  sources <- vapply(expected$files, function(item) {
    path <- file.path(root, sub("^participant/", "", item$path))
    .brohn_runner_require(file.exists(path) && !dir.exists(path), "An assigned study player file is unavailable.", 503L)
    path <- normalizePath(path, winslash = "/", mustWork = TRUE)
    compared <- if (.Platform$OS.type == "windows") tolower(path) else path
    directory <- if (.Platform$OS.type == "windows") tolower(root) else root
    .brohn_runner_require(startsWith(compared, paste0(directory, "/")), "Assigned runtime files must stay in their registered distribution.", 503L)
    path
  }, character(1))
  bytes <- lapply(seq_along(sources), function(i) {
    item <- expected$files[[i]]; path <- sources[[i]]
    .brohn_runner_require(identical(as.numeric(file.info(path)$size), as.numeric(item$size)), "The installed assigned player size changed.", 503L)
    value <- readBin(path, "raw", n = item$size + 1L)
    .brohn_runner_require(length(value) == item$size && identical(.brohn_runner_hash(value), item$hash),
      "The installed assigned player differs from its registered source bytes.", 503L)
    value
  })
  names(bytes) <- vapply(expected$files, `[[`, character(1), "path")
  # Publication uses these retained raw bytes. A changed file cannot be silently
  # substituted between preparation and preserving the release's code objects.
  for (i in seq_along(sources)) .brohn_runner_require(identical(readBin(sources[[i]], "raw", n = expected$files[[i]]$size + 1L), bytes[[i]]),
    "Assigned player files changed during preparation. Retry after installation finishes.", 503L)
  list(manifest = expected, hash = brohn_hash(expected), bytes = bytes)
}

# Trusted application startup only. The caller is the installed loader, never a
# saved study, portable archive, participant request or uploaded file declaration.
brohn_install_assigned_runtime <- function(static_root, envir = environment(brohn_install_assigned_runtime)) {
  prepared <- brohn_assigned_runtime_prepare(static_root)
  registration <- list(profile = "participant-view-delivery/0.1", renderer_id = prepared$manifest$renderer_id,
    runtime_manifest_hash = prepared$hash)
  if (exists(".brohn_assigned_runtime_installation", envir, inherits = FALSE)) {
    old <- get(".brohn_assigned_runtime_installation", envir, inherits = FALSE)
    .brohn_runner_require(identical(old$registration, registration), "Restart with the matching installed assigned player; do not replace a live registration.", 503L)
    return(invisible(registration))
  }
  .brohn_runner_require(exists(".brohn_runner_manifest", envir, inherits = FALSE) &&
    !exists(".brohn_participant_view_renderer_registration", envir, inherits = FALSE),
    "Install the assigned runtime into a complete, unregistered domain namespace.", 503L)
  brohn_install_assigned_runtime_reader(envir)
  reader <- get(".brohn_assigned_runtime_reader", envir, inherits = FALSE)
  renderer <- local({saved <- registration; function() saved})
  # Explicit installation only. No source file, brohn_publish implementation,
  # legacy manifest value or historical code object is rewritten.
  assign(".brohn_participant_view_renderer_registration", renderer, envir)
  assign(".brohn_assigned_runtime_installation", list(registration = registration,
    original_manifest = reader$original_manifest, prepared = prepared), envir)
  invisible(registration)
}

.brohn_assigned_runtime_installed <- function() {
  namespace <- environment(.brohn_assigned_runtime_installed)
  .brohn_runner_require(exists(".brohn_assigned_runtime_installation", namespace, inherits = FALSE),
    "The installed participant player is unavailable. Start the matching Brohn service.", 503L)
  installed <- get(".brohn_assigned_runtime_installation", namespace, inherits = FALSE)
  .brohn_assigned_runtime_manifest(installed$prepared$manifest, installed$prepared$hash)
  .brohn_runner_require(identical(installed$registration, .brohn_pvds_registration()) &&
    identical(installed$registration$runtime_manifest_hash, installed$prepared$hash),
    "The installed participant player registration changed.", 503L)
  installed
}
