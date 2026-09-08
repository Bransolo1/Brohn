# Read-only lockfile/library check in a fresh R process, without library fallback.
# Usage: Rscript --vanilla scripts/check-dependencies.R [target-library]
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) {
  stop("Usage: Rscript --vanilla scripts/check-dependencies.R [target-library]", call. = FALSE)
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
project <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
target_library <- if (length(args)) args[[1L]] else file.path(project, "renv/library")
if (!dir.exists(target_library)) {
  stop("Target library does not exist. Run scripts/restore-dependencies.R first: ", target_library,
       call. = FALSE)
}
target_library <- normalizePath(target_library, winslash = "/", mustWork = TRUE)
.libPaths(c(target_library, .Library), include.site = FALSE)
if (!requireNamespace("renv", quietly = TRUE, lib.loc = target_library)) {
  stop("Target library has no usable renv package. Run the restore script first.", call. = FALSE)
}
lock <- renv::lockfile_read(file.path(project, "renv.lock"))
if (as.character(getRversion()) != lock$R$Version) {
  stop("R version mismatch: lock = ", lock$R$Version, "; running = ", getRversion(), call. = FALSE)
}
installed <- installed.packages(lib.loc = target_library, fields = c("Repository", "License"))
locked <- vapply(lock$Packages, function(record) record$Version, character(1L))
missing <- setdiff(names(locked), rownames(installed))
if (length(missing)) stop("Missing locked packages: ", paste(missing, collapse = ", "), call. = FALSE)
different <- names(locked)[installed[names(locked), "Version"] != locked]
if (length(different)) {
  stop("Version mismatch: ", paste(sprintf("%s (installed %s; lock %s)", different,
       installed[different, "Version"], locked[different]), collapse = ", "), call. = FALSE)
}
for (package in names(locked)) {
  if (!requireNamespace(package, quietly = TRUE, lib.loc = target_library)) {
    stop("Cannot load locked package namespace: ", package, call. = FALSE)
  }
  expected_path <- normalizePath(file.path(target_library, package), winslash = "/", mustWork = TRUE)
  loaded_path <- normalizePath(getNamespaceInfo(asNamespace(package), "path"), winslash = "/", mustWork = TRUE)
  if (!identical(expected_path, loaded_path)) {
    stop("Package loaded from a different library: ", package, "; restart with Rscript --vanilla.", call. = FALSE)
  }
  if (as.character(getNamespaceVersion(package)) != locked[[package]]) {
    stop("Loaded namespace version mismatch: ", package, call. = FALSE)
  }
  record <- lock$Packages[[package]]
  if (!identical(record$Source, "Repository") || !identical(record$Repository, "CRAN") ||
      !identical(unname(installed[package, "Repository"]), record$Repository) ||
      !identical(unname(installed[package, "License"]), record$License)) {
    stop("Source/license metadata differs from the lockfile: ", package, call. = FALSE)
  }
}
extras <- setdiff(rownames(installed), names(locked))
cat(sprintf("PASS: R %s; %d/%d locked versions match and namespaces load from %s.\n",
            lock$R$Version, length(locked), length(locked), target_library))
cat(sprintf("CRAN source and license declarations match for all locked packages; %d extra installed packages.\n",
            length(extras)))
if (length(extras)) cat("Extra packages: ", paste(extras, collapse = ", "), "\n", sep = "")
