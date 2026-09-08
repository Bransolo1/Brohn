# Explicit restore; no renv activation or changes to the current application library.
# Usage: Rscript --vanilla scripts/restore-dependencies.R [target-library]
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) {
  stop("Usage: Rscript --vanilla scripts/restore-dependencies.R [target-library]", call. = FALSE)
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
project <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
target_library <- if (length(args)) args[[1L]] else file.path(project, "renv/library")
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT"))) {
  Sys.setenv(RENV_PATHS_ROOT = file.path(project, "renv/library/.renv-state"))
}
if (!requireNamespace("renv", quietly = TRUE)) {
  stop("renv is unavailable on R's library paths. Install it in an explicit bootstrap library and set R_LIBS_USER; see docs/preparation/R-TOOLING.md.",
       call. = FALSE)
}
lockfile <- file.path(project, "renv.lock")
if (!file.exists(lockfile)) stop("Missing lockfile: ", lockfile, call. = FALSE)
lock <- renv::lockfile_read(lockfile)
if (as.character(getRversion()) != lock$R$Version) {
  stop("This lock records R ", lock$R$Version, "; current R is ", getRversion(),
       ". Use the recorded R version for the checked restore workflow.", call. = FALSE)
}
dir.create(target_library, recursive = TRUE, showWarnings = FALSE)
target_library <- normalizePath(target_library, winslash = "/", mustWork = TRUE)
if (identical(target_library, normalizePath(.Library, winslash = "/"))) {
  stop("Choose a separate target library, not R's base library.", call. = FALSE)
}
cat("Restoring into: ", target_library, "\n", sep = "")
renv::restore(
  project = project,
  library = target_library,
  lockfile = lockfile,
  clean = FALSE,
  transactional = TRUE,
  retry = FALSE,
  prompt = FALSE
)
installed <- installed.packages(lib.loc = target_library)
locked <- vapply(lock$Packages, function(record) record$Version, character(1L))
missing <- setdiff(names(locked), rownames(installed))
if (length(missing)) stop("Restore is missing packages: ", paste(missing, collapse = ", "), call. = FALSE)
if (!identical(unname(installed[names(locked), "Version"]), unname(locked))) {
  stop("Restored package versions do not match renv.lock.", call. = FALSE)
}
cat(sprintf("Restored metadata matches all %d locked versions. Run scripts/check-dependencies.R with this target in a fresh R process to verify namespace loading.\n",
            length(locked)))
