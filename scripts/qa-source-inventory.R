# Source bytes used by local QA, including nested installed profiles and assets.
# This reads a checkout, never a configured research workspace. It neither
# installs nor trusts executable code supplied in an imported study design.
brohn_qa_source_inventory <- function(project) {
  root <- normalizePath(project, winslash = "/", mustWork = TRUE)
  if (!dir.exists(root)) stop("QA source root is not a directory.", call. = FALSE)
  key <- function(path) if (.Platform$OS.type == "windows") tolower(path) else path
  checked <- function(relative) {
    lexical <- paste0(root, "/", relative)
    link <- Sys.readlink(lexical)
    if (!is.na(link) && nzchar(link)) stop("QA source cannot contain a symbolic link: ", relative, call. = FALSE)
    resolved <- normalizePath(lexical, winslash = "/", mustWork = TRUE)
    if (!identical(key(resolved), key(lexical)))
      stop("QA source cannot contain a junction or path alias: ", relative, call. = FALSE)
    resolved
  }
  # Cache exclusions are deliberately narrow. Research stores, recordings,
  # installed dependency trees and QA outputs are not source roots at all.
  cache_directories <- c("__pycache__", ".pytest_cache", ".mypy_cache")
  paths <- character()
  walk <- function(relative) {
    directory <- checked(relative)
    if (file.access(directory, 4L) != 0L) stop("QA source directory cannot be read: ", relative, call. = FALSE)
    entries <- list.files(directory, all.files = TRUE, no.. = TRUE, full.names = FALSE)
    for (name in entries) {
      child <- paste0(relative, "/", name)
      # Test execution can produce Python bytecode. It is not source evidence.
      if (name %in% cache_directories || grepl("\\.py[co]$", name)) next
      path <- checked(child)
      if (dir.exists(path)) walk(child) else {
        info <- file.info(path)
        if (is.na(info$size) || !isFALSE(info$isdir))
          stop("QA source cannot be read: ", child, call. = FALSE)
        paths <<- c(paths, child)
      }
    }
  }
  required <- c("R", "src", "scripts", "www", "tests")
  for (folder in required) {
    if (!dir.exists(file.path(root, folder))) stop("Missing QA source directory: ", folder, call. = FALSE)
    walk(folder)
  }
  for (folder in c("registry", "config", "examples")) {
    if (dir.exists(file.path(root, folder))) walk(folder)
    else if (file.exists(file.path(root, folder))) stop("QA source root must be a directory: ", folder, call. = FALSE)
  }
  root_files <- list.files(root, all.files = TRUE, no.. = TRUE, full.names = FALSE)
  root_files <- root_files[grepl("\\.(R|py|js|mjs|css|ps1)$", root_files) |
    root_files %in% c("renv.lock", "package.json", "pnpm-lock.yaml", "package-lock.json", "yarn.lock", ".gitattributes", ".gitignore")]
  for (relative in root_files) {
    path <- checked(relative)
    if (dir.exists(path)) stop("Expected a root source file: ", relative, call. = FALSE)
    paths <- c(paths, relative)
  }
  if (!"renv.lock" %in% paths) stop("Missing QA dependency lock: renv.lock", call. = FALSE)
  paths <- sort(unique(paths), method = "radix")
  stats::setNames(lapply(paths, function(relative)
    digest::digest(file = checked(relative), algo = "sha256")), paths)
}
