# Portable, design-only packages for the local workspace profile. This module
# never deploys a study, executes an uploaded recipe, or fetches dependencies.
# Load platform-core.R and platform-store.R first.
.brohn_portability_source <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.brohn_portability_helper <- normalizePath(file.path(
  if (is.null(.brohn_portability_source)) "." else dirname(dirname(.brohn_portability_source)),
  "scripts", "portable-design.py"), winslash = "/", mustWork = FALSE)

.brohn_port_python <- function() {
  configured <- Sys.getenv("BROHN_PYTHON", "")
  candidates <- if (nzchar(configured)) configured else c(
    file.path("..", "..", "work", "tooling", "methods-venv", "Scripts", "python.exe"),
    file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Python", "Python312", "python.exe"),
    unname(Sys.which("python3")), unname(Sys.which("python")))
  candidates <- candidates[nzchar(candidates) & file.exists(candidates) & !dir.exists(candidates)]
  brohn_require(length(candidates) > 0, "Portable design validation needs Python 3.9+; configure BROHN_PYTHON with its executable path.")
  normalizePath(candidates[[1]], winslash = "/", mustWork = TRUE)
}
.brohn_port_call <- function(arguments) {
  brohn_require(requireNamespace("processx", quietly = TRUE), "Portable design validation requires the pinned processx package.")
  brohn_require(file.exists(.brohn_portability_helper), "The portable-design validator is missing from this Brohn installation.")
  result <- processx::run(.brohn_port_python(), c(.brohn_portability_helper, arguments),
    echo = FALSE, error_on_status = FALSE, timeout = 120, cleanup_tree = TRUE, windows_hide_window = TRUE)
  if (result$status != 0L) {
    detail <- tryCatch(brohn_parse(trimws(result$stdout))$error, error = function(e) NULL)
    brohn_stop(paste("Design package rejected:", brohn_default(detail, substr(trimws(paste(result$stdout, result$stderr)), 1, 1800))))
  }
  invisible(brohn_parse(trimws(result$stdout)))
}
.brohn_port_temp <- function() {
  path <- tempfile("brohn-port-", tmpdir = tempdir())
  brohn_require(dir.create(path), "Cannot create the isolated design validation directory.")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}
.brohn_port_cleanup <- function(path) {
  parent <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  candidate <- normalizePath(path, winslash = "/", mustWork = FALSE)
  compare_parent <- parent; compare_candidate <- candidate
  if (.Platform$OS.type == "windows") {compare_parent <- tolower(parent); compare_candidate <- tolower(candidate)}
  link <- Sys.readlink(candidate)
  if (startsWith(compare_candidate, paste0(compare_parent, "/")) &&
      grepl("^brohn-port-", basename(candidate)) && (is.na(link) || !nzchar(link))) {
    unlink(candidate, recursive = TRUE, force = TRUE)
  }
  invisible(NULL)
}
.brohn_port_read <- function(path) {
  brohn_require(file.exists(path) && !dir.exists(path) && file.info(path)$size <= 16*1024^2,
    "Design document is missing or exceeds 16 MiB.")
  text <- rawToChar(readBin(path, "raw", n = file.info(path)$size))
  Encoding(text) <- "UTF-8"
  brohn_parse(text)
}
.brohn_port_write <- function(value, path) {
  bytes <- charToRaw(enc2utf8(brohn_json(value)))
  brohn_require(length(bytes) <= 16*1024^2, "Design document exceeds 16 MiB.")
  writeBin(bytes, path)
}
.brohn_port_formats <- function() c("image/png" = ".png", "image/jpeg" = ".jpg", "image/webp" = ".webp",
  "audio/wav" = ".wav", "audio/mpeg" = ".mp3", "audio/ogg" = ".ogg",
  "video/mp4" = ".mp4", "video/webm" = ".webm")
.brohn_port_validate <- function(design) {
  brohn_validate_design(design)
  if (length(design$blocks)) {
    brohn_require(exists("brohn_task_validate", mode = "function") && exists("brohn_task_clone", mode = "function"), "Task designs require their registered validator and identity mapper.")
    lapply(design$blocks, brohn_task_validate)
  }
  brohn_require(length(design$methods) == 0,
    "This package profile cannot remap unregistered analysis recipes yet. No recipe settings were dropped or executed.")
  if (!is.null(design$lineage)) {
    brohn_validate_lineage(design$lineage)
    brohn_require(is.list(design$lineage) && !is.null(names(design$lineage)) &&
      all(names(design$lineage) %in% c("operation", "study_id", "design_hash", "revision", "package_hash", "source_revision", "template_id", "template_revision", "origin")),
      "Design lineage contains unsupported fields. Remove private operational metadata before export.")
    for (field in intersect(names(design$lineage), c("design_hash", "package_hash")))
      brohn_require(brohn_text(design$lineage[[field]], 64) && grepl("^[a-f0-9]{64}$", design$lineage[[field]]), "Invalid design lineage hash.")
    if (!is.null(design$lineage$study_id)) brohn_require(brohn_valid_id(design$lineage$study_id), "Invalid source study identity.")
    if (!is.null(design$lineage$operation)) brohn_require(design$lineage$operation %in% c("clone_design", "legacy_import", "import_design", "use_template", "original_sample_design"), "Unsupported lineage operation.")
    if (!is.null(design$lineage$revision)) brohn_require(brohn_number(design$lineage$revision, 1, .Machine$integer.max, TRUE), "Invalid source revision.")
  }
  for (stimulus in design$stimuli) {
    if (stimulus$type == "web") brohn_require(grepl("^https://[A-Za-z0-9][A-Za-z0-9.-]*(?::[0-9]+)?(?:/[^?#[:space:]]*)?$", stimulus$content, perl = TRUE),
      "Portable web stimuli need a public HTTPS URL without credentials, query tokens or fragments. No page is downloaded or embedded.")
    if (!is.null(stimulus$asset)) {
      asset <- stimulus$asset
      brohn_require(asset$media_type %in% names(.brohn_port_formats()), "This media type is not supported by the portable design profile.")
      expected_type <- if (startsWith(asset$media_type, "image/")) "image" else if (startsWith(asset$media_type, "audio/")) "audio" else "video"
      brohn_require(identical(stimulus$type, expected_type), "Stimulus kind and asset media type disagree.")
      if (!is.null(asset$filename)) brohn_require(brohn_text(asset$filename, 240) &&
        !grepl("[/\\\\:]", asset$filename) && !asset$filename %in% c(".", ".."),
        "Asset filename must be a plain display name, not a private filesystem path.")
      if (!is.null(asset$width)) brohn_require(brohn_number(asset$width, 1, 32768, TRUE), "Invalid asset width.")
      if (!is.null(asset$height)) brohn_require(brohn_number(asset$height, 1, 32768, TRUE), "Invalid asset height.")
    }
  }
  for (block in design$blocks) for (material in block$materials) if (!is.null(material$asset)) {
    asset <- material$asset
    brohn_require(asset$media_type %in% names(.brohn_port_formats()), "This task image type is not supported by the portable design profile.")
    if (!is.null(asset$filename)) brohn_require(brohn_text(asset$filename, 240) &&
      !grepl("[/\\\\:]", asset$filename) && !asset$filename %in% c(".", ".."), "Task image filename must be a plain display name, not a private filesystem path.")
    if (!is.null(asset$width)) brohn_require(brohn_number(asset$width, 1, 32768, TRUE), "Invalid task image width.")
    if (!is.null(asset$height)) brohn_require(brohn_number(asset$height, 1, 32768, TRUE), "Invalid task image height.")
  }
  invisible(design)
}
.brohn_port_aois <- function(design) list(schema_version = "brohn-aoi-design/1.0",
  stimuli = lapply(design$stimuli, function(s) list(stimulus_id = s$id, regions = s$aois)))
.brohn_port_recipes <- function(design) {
  result <- list(schema_version = "brohn-recipes/1.0", methods = design$methods)
  if (!is.null(design$analysis_plan)) result$analysis_plan <- design$analysis_plan
  if (!is.null(design$scales)) result$scales <- design$scales
  if (!is.null(design$maxdiff)) result$maxdiff <- design$maxdiff
  if (length(design$blocks)) result$tasks <- lapply(design$blocks, function(b) list(task_id = b$id, profile = b$profile, block_hash = brohn_hash(b)))
  result
}
.brohn_port_dependencies <- function(design) list(schema_version = "brohn-dependencies/1.0",
  measures = design$measures, models = list(), missing_assets = lapply(Filter(function(s)
    s$type %in% c("image", "audio", "video") && is.null(s$asset), design$stimuli),
    function(s) list(stimulus_id = s$id, reason = "asset_not_attached")), rights = "researcher_review_required")
.brohn_port_assets <- function(design) {
  assets <- Filter(Negate(is.null), lapply(design$stimuli, function(s) s$asset))
  for (block in design$blocks) assets <- c(assets, Filter(Negate(is.null), lapply(block$materials, function(m) m$asset)))
  unique <- list()
  for (asset in assets) {
    old <- unique[[asset$hash]]
    if (!is.null(old)) brohn_require(identical(old$media_type, asset$media_type) && old$size == asset$size,
      "The same asset hash has inconsistent media metadata.")
    else unique[[asset$hash]] <- asset
  }
  unique
}

brohn_export_design <- function(store, study_id, destination, revision = NULL) {
  .brohn_store_ready(store)
  entity <- brohn_get_entity(store, "study", study_id, revision)
  brohn_require(!is.null(entity), "The selected study revision does not exist.")
  design <- entity$body; .brohn_port_validate(design)
  brohn_require(identical(entity$id, design$id) && identical(entity$project_id, design$project_id),
    "Stored study identity or project is inconsistent with its design.")
  brohn_require(brohn_text(destination, 4096) && !file.exists(destination), "Choose a new export filename; existing files are not overwritten.")
  brohn_require(dir.exists(dirname(destination)), "The export destination folder does not exist.")
  destination <- file.path(normalizePath(dirname(destination), winslash = "/", mustWork = TRUE), basename(destination))
  brohn_require(grepl("\\.brohn-study\\.zip$", destination, ignore.case = TRUE), "Use the .brohn-study.zip file extension.")
  stage <- .brohn_port_temp(); on.exit(.brohn_port_cleanup(stage), add = TRUE)
  .brohn_port_write(design, file.path(stage, "design.json"))
  .brohn_port_write(.brohn_port_aois(design), file.path(stage, "aoi.json"))
  .brohn_port_write(.brohn_port_recipes(design), file.path(stage, "recipes.json"))
  .brohn_port_write(.brohn_port_dependencies(design), file.path(stage, "dependencies.json"))
  files <- lapply(c("design.json", "aoi.json", "recipes.json", "dependencies.json"), function(name)
    list(path = name, sha256 = digest::digest(file = file.path(stage, name), algo = "sha256"),
      size = as.numeric(file.info(file.path(stage, name))$size), media_type = "application/json"))
  assets <- .brohn_port_assets(design)
  if (length(assets)) brohn_require(dir.create(file.path(stage, "assets")), "Cannot stage portable assets.")
  for (asset in assets) {
    source <- brohn_object_path(store, asset$hash, verify = TRUE)
    brohn_require(file.info(source)$size == asset$size, "Design asset size differs from its immutable object.")
    relative <- paste0("assets/", asset$hash, .brohn_port_formats()[[asset$media_type]])
    brohn_require(file.copy(source, file.path(stage, relative), overwrite = FALSE), "Cannot stage an export asset.")
    files[[length(files)+1L]] <- list(path = relative, sha256 = asset$hash, size = asset$size, media_type = asset$media_type)
  }
  manifest <- list(schema_version = "brohn-study-package/1.0", design_schema_version = design$schema_version,
    product = "Brohn", exported_at = brohn_now(), source = list(study_id = design$id,
      revision = entity$revision, design_hash = brohn_hash(design)), files = files,
    rights = "researcher_review_required")
  .brohn_port_write(manifest, file.path(stage, "manifest.json"))
  .brohn_port_call(c("validate-directory", "--directory", stage))
  brohn_require(requireNamespace("zip", quietly = TRUE), "Portable design export needs the pinned zip package.")
  temporary_zip <- tempfile(".brohn-export-", tmpdir = dirname(destination), fileext = ".zip")
  on.exit(unlink(temporary_zip), add = TRUE)
  zip::zipr(temporary_zip, files = c("manifest.json", vapply(files, function(x) x$path, character(1))),
    root = stage, mode = "mirror", recurse = FALSE, include_directories = FALSE, compression_level = 0)
  # Verify the produced container as well as its input files before publication.
  verification <- .brohn_port_temp(); on.exit(.brohn_port_cleanup(verification), add = TRUE)
  .brohn_port_call(c("extract", "--archive", temporary_zip, "--quarantine", verification))
  # An atomic hard-link publication cannot replace a concurrently created file.
  brohn_require(!file.exists(destination) && file.link(temporary_zip, destination),
    "Could not publish the export without overwriting a file. Choose a writable local destination that supports hard links.")
  normalizePath(destination, winslash = "/", mustWork = TRUE)
}

brohn_import_design <- function(store, path, title = NULL, project_id = "default") {
  .brohn_store_ready(store)
  brohn_require(brohn_text(path, 4096) && file.exists(path) && !dir.exists(path), "Choose an existing .brohn-study.zip package.")
  brohn_require(file.info(path)$size <= 512*1024^2, "Design archive exceeds the 512 MiB import limit.")
  package_hash <- digest::digest(file = path, algo = "sha256")
  brohn_require(brohn_valid_id(project_id), "Choose a valid destination project.")
  if (!is.null(title)) brohn_require(brohn_text(title, 240), "The imported study needs a valid title.")
  quarantine <- .brohn_port_temp(); on.exit(.brohn_port_cleanup(quarantine), add = TRUE)
  .brohn_port_call(c("extract", "--archive", normalizePath(path, winslash = "/", mustWork = TRUE), "--quarantine", quarantine))
  manifest <- .brohn_port_read(file.path(quarantine, "manifest.json"))
  design <- .brohn_port_read(file.path(quarantine, "design.json")); .brohn_port_validate(design)
  brohn_require(identical(manifest$source$study_id, design$id) && identical(manifest$source$design_hash, brohn_hash(design)), "Package source design identity/hash is inconsistent.")
  brohn_require(identical(brohn_hash(.brohn_port_read(file.path(quarantine, "aoi.json"))), brohn_hash(.brohn_port_aois(design))), "AOI document disagrees with the canonical design.")
  brohn_require(identical(brohn_hash(.brohn_port_read(file.path(quarantine, "recipes.json"))), brohn_hash(.brohn_port_recipes(design))), "Recipe document disagrees with the canonical design.")
  brohn_require(identical(brohn_hash(.brohn_port_read(file.path(quarantine, "dependencies.json"))), brohn_hash(.brohn_port_dependencies(design))), "Dependencies contain unsupported or inconsistent model/asset requirements.")
  assets <- .brohn_port_assets(design)
  packaged_assets <- Filter(function(file) startsWith(file$path, "assets/"), manifest$files)
  brohn_require(length(packaged_assets) == length(assets), "Package has missing or unreferenced design assets.")
  for (file in packaged_assets) {
    asset <- assets[[file$sha256]]
    brohn_require(!is.null(asset) && asset$size == file$size && identical(asset$media_type, file$media_type), "Packaged asset is not an exact referenced design asset.")
  }
  result <- brohn_clone_design(design, brohn_default(title, paste(design$title, "imported")), project_id)
  result$lineage <- list(operation = "import_design", study_id = manifest$source$study_id,
    design_hash = manifest$source$design_hash, revision = manifest$source$revision,
    package_hash = package_hash)
  .brohn_port_validate(result)
  brohn_require(identical(package_hash, digest::digest(file = path, algo = "sha256")),
    "The source package changed during validation. Retry using a stable local copy.")
  save_import <- function() {
    for (file in packaged_assets) {
      registered <- brohn_store_object(store, path = file.path(quarantine, file$path), media_type = file$media_type)
      brohn_require(identical(registered$hash, file$sha256) && registered$size == file$size, "Imported object changed during registration.")
    }
    brohn_put_entity(store, "study", result$id, result, expected_revision = 0L, project_id = project_id,
      operation_id = brohn_id("design-import"))
  }
  # The store batch wraps all registrations and the new study.
  # Content-addressed orphan bytes can be reconciled after a rolled-back crash.
  brohn_require(exists("brohn_store_batch", mode = "function"), "Portable import needs a transaction-capable Brohn catalog.")
  brohn_store_batch(store, save_import)
}
