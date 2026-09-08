# Deliberate lockfile update from an already installed, tested library.
# Usage: Rscript --vanilla scripts/snapshot-dependencies.R <source-library>
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript --vanilla scripts/snapshot-dependencies.R <source-library>",
       call. = FALSE)
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
project <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source_library <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
.libPaths(c(source_library, .Library), include.site = FALSE)
if (!nzchar(Sys.getenv("RENV_PATHS_ROOT"))) {
  Sys.setenv(RENV_PATHS_ROOT = file.path(project, "renv/library/.renv-state"))
}
if (!requireNamespace("renv", quietly = TRUE, lib.loc = source_library)) {
  stop("renv is missing from the source library. Install renv there explicitly first; see docs/preparation/R-TOOLING.md.",
       call. = FALSE)
}
source(file.path(project, "scripts", "runtime-dependencies.R"), encoding = "UTF-8")
packages <- c(brohn_runtime_packages, "renv")
installed <- installed.packages(lib.loc = source_library)
missing <- setdiff(packages, rownames(installed))
if (length(missing)) stop("Source library is missing: ", paste(missing, collapse = ", "), call. = FALSE)
lock <- renv::snapshot(
  project = project,
  library = source_library,
  lockfile = file.path(project, "renv.lock"),
  packages = packages,
  repos = c(CRAN = "https://cloud.r-project.org"),
  prompt = FALSE,
  force = FALSE
)
locked <- vapply(lock$Packages, function(record) record$Version, character(1L))
if (anyNA(installed[names(locked), "Version"]) ||
    !identical(unname(installed[names(locked), "Version"]), unname(locked))) {
  stop("Snapshot verification failed: recorded versions differ from the source library.", call. = FALSE)
}
cat(sprintf("Snapshot verified: %d exact package versions; R %s. Review renv.lock before accepting an update.\n",
            length(locked), lock$R$Version))
