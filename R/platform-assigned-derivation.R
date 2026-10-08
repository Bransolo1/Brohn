# Trusted startup registration for original participant event derivation.
# The manifest is installed application source, never part of study portability.
brohn_register_assigned_derivation <- function(envir = environment(brohn_register_assigned_derivation)) {
  installed <- .brohn_assigned_runtime_installed()
  manifest_path <- "config/assigned-delivery-sources.json"
  .brohn_pvr_require(file.exists(manifest_path) && !dir.exists(manifest_path) &&
    file.info(manifest_path)$size <= 1024^2, "The installed response source manifest is unavailable.", "derivation_unavailable", 503L)
  raw <- readBin(manifest_path, "raw", n = 1024^2 + 1L)
  manifest <- .brohn_pvds_decode(raw)
  brohn_fields(manifest, c("schema", "files"), label = "Installed response source manifest")
  .brohn_pvr_require(identical(manifest$schema, "assigned-delivery-source/0.1") && brohn_array(manifest$files) &&
    length(manifest$files) > 0L, "The installed response source manifest is invalid.", "derivation_unavailable", 503L)
  root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  descriptor <- list(schema = "participant-view-derivation-implementation/0.1", profile = .brohn_pvr_profile,
    assigned_profile = "participant-view-delivery/0.1", renderer_identity = .brohn_pvds_renderer(installed$registration),
    runtime = list(r_version = as.character(getRversion()), platform = R.version$platform), files = manifest$files,
    packages = lapply(c("DBI", "RSQLite", "jsonlite", "digest"), function(name)
      list(name = name, version = as.character(utils::packageVersion(name)))))
  .brohn_pvr_identity_validate(descriptor)
  verify <- function() for (file in manifest$files) {
    .brohn_pvr_require(startsWith(file$path, "R/") && endsWith(file$path, ".R") ||
      file$path %in% c("scripts/run-participant.R", "scripts/run-worker.R", "scripts/variant-analysis-worker.R"),
      "The response manifest must describe installed application source only.", "derivation_unavailable", 503L)
    .brohn_pvr_require(file.exists(file$path) && !dir.exists(file$path),
      "A registered response source file is unavailable.", "derivation_unavailable", 503L)
    actual <- normalizePath(file$path, winslash = "/", mustWork = TRUE)
    compared <- if (.Platform$OS.type == "windows") tolower(actual) else actual
    directory <- if (.Platform$OS.type == "windows") tolower(root) else root
    .brohn_pvr_require(startsWith(compared, paste0(directory, "/")) &&
      file.info(actual)$size == file$bytes && identical(digest::digest(file = actual, algo = "sha256"), file$sha256),
      "The response implementation differs from its installed source manifest.", "derivation_unavailable", 503L)
  }
  verify()
  .brohn_pvr_require(identical(readBin(manifest_path, "raw", n = 1024^2 + 1L), raw),
    "The response source manifest changed during startup.", "derivation_unavailable", 503L)
  # Include the manifest as original evidence without a circular self-hash in
  # its own contents. It is not sourced or used as an executable profile.
  descriptor$files <- c(descriptor$files, list(list(path = manifest_path,
    bytes = length(raw), sha256 = .brohn_pvds_sha(raw))))
  .brohn_pvr_identity_validate(descriptor)
  if (exists(".brohn_participant_view_derivation_registration", envir, inherits = FALSE)) {
    old <- get(".brohn_participant_view_derivation_registration", envir, inherits = FALSE)()
    .brohn_pvr_require(.brohn_ph_equal(old, descriptor), "Restart with the matching response implementation.", "derivation_unavailable", 503L)
    return(invisible(descriptor))
  }
  registered <- local({saved <- descriptor; function() saved})
  assign(".brohn_participant_view_derivation_registration", registered, envir)
  invisible(descriptor)
}
