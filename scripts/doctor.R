# Read-only setup report. No application store is opened and no packages, model
# weights, device sessions or network connections are created by these checks.
.brohn_doctor_source <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.brohn_doctor_profiles <- c("methods", "acquisition", "vision-audio", "segmentation", "facial-au")

brohn_doctor_json <- function(x) {
  # A dependency-free fallback must still report a completely missing R library.
  quote_text <- function(s) {
    chars <- utf8ToInt(enc2utf8(s))
    paste0('"', paste(vapply(chars, function(n) {
      if (n == 34) '\\"' else if (n == 92) '\\\\' else if (n < 32) sprintf("\\u%04x", n) else intToUtf8(n)
    }, character(1)), collapse = ""), '"')
  }
  if (is.null(x)) return("null")
  if (is.list(x)) {
    named <- length(x) && !is.null(names(x)) && all(nzchar(names(x)))
    values <- vapply(x, brohn_doctor_json, character(1))
    if (named) return(paste0("{", paste(paste0(vapply(names(x), quote_text, character(1)), ":", values), collapse = ","), "}"))
    return(paste0("[", paste(values, collapse = ","), "]"))
  }
  if (length(x) != 1L) return(brohn_doctor_json(as.list(x)))
  if (is.na(x)) return("null")
  if (is.logical(x)) return(if (x) "true" else "false")
  if (is.numeric(x)) return(if (is.finite(x)) format(x, scientific = FALSE, trim = TRUE, digits = 17) else "null")
  quote_text(as.character(x))
}

brohn_doctor_core <- function(project, library) {
  result <- list(status = "not_ready", library = normalizePath(library, winslash = "/", mustWork = FALSE),
    r_version = as.character(getRversion()), packages = list(), direct_dependencies = list())
  if (!dir.exists(library)) {result$message <- "The selected R library does not exist. Explicitly restore renv.lock into a separate library."; return(result)}
  library <- normalizePath(library, winslash = "/", mustWork = TRUE)
  old <- .libPaths(); on.exit(.libPaths(old), add = TRUE)
  .libPaths(c(library, .Library), include.site = FALSE)
  exact_namespace <- function(package) {
    if (!requireNamespace(package, quietly = TRUE, lib.loc = library)) return(FALSE)
    identical(normalizePath(getNamespaceInfo(asNamespace(package), "path"), winslash = "/"), normalizePath(file.path(library, package), winslash = "/", mustWork = FALSE))
  }
  if (!tryCatch(exact_namespace("jsonlite"), error = function(e) FALSE)) {
    result$message <- "The selected library has no usable jsonlite namespace, or another library was already loaded. Restore the lock and run Rscript --vanilla in a fresh process."
    return(result)
  }
  lockpath <- file.path(project, "renv.lock")
  if (!file.exists(lockpath) || file.info(lockpath)$size > 2*1024^2) {result$message <- "The R lockfile is missing or exceeds its inspection bound."; return(result)}
  lock <- tryCatch(jsonlite::fromJSON(lockpath, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(lock$Packages) || is.null(lock$R$Version)) {result$message <- "The R lockfile could not be parsed."; return(result)}
  environment <- new.env(parent = baseenv()); sys.source(file.path(project, "scripts/runtime-dependencies.R"), envir = environment)
  direct <- environment$brohn_runtime_packages
  installed <- installed.packages(lib.loc = library, fields = c("Repository", "License"))
  result$expected_r_version <- lock$R$Version
  result$r_matches <- identical(result$r_version, lock$R$Version)
  result$packages <- lapply(names(lock$Packages), function(name) {
    p <- lock$Packages[[name]]
    item <- list(name = name, expected = p$Version, actual = if (name %in% rownames(installed)) unname(installed[name, "Version"]) else NULL,
      direct = name %in% direct, status = "missing", namespace = "not_loaded")
    if (is.null(item$actual)) return(item)
    item$status <- if (identical(item$actual, p$Version)) "ready" else "mismatch"
    item$source_matches <- identical(p$Source, "Repository") && identical(p$Repository, "CRAN") &&
      identical(unname(installed[name, "Repository"]), p$Repository) && identical(unname(installed[name, "License"]), p$License)
    loaded <- tryCatch(exact_namespace(name), error = function(e) FALSE)
    item$namespace <- if (loaded) "loaded_from_selected_library" else "failed_or_foreign_library"
    if (loaded && as.character(getNamespaceVersion(name)) != p$Version) item$namespace <- "version_mismatch"
    if (!isTRUE(item$source_matches) || item$namespace != "loaded_from_selected_library") item$status <- "mismatch"
    item
  })
  result$direct_dependencies <- lapply(direct, function(name) list(name = name, declared_in_lock = name %in% names(lock$Packages)))
  result$extras <- as.list(setdiff(rownames(installed), names(lock$Packages)))
  result$status <- if (result$r_matches && all(vapply(result$packages, function(p) p$status == "ready", logical(1))) &&
    all(vapply(result$direct_dependencies, function(p) p$declared_in_lock, logical(1)))) "ready" else "not_ready"
  if (result$status != "ready") result$message <- "Restore the exact lock into the selected library and rerun in a fresh Rscript --vanilla process; no library fallback or upgrade was applied."
  result
}

brohn_doctor_python_path <- function(profile, project) {
  if (profile == "portability") {
    configured <- Sys.getenv("BROHN_PYTHON", "")
    candidates <- if (nzchar(configured)) configured else c(file.path(project, "../../work/tooling/methods-venv/Scripts/python.exe"),
      file.path(Sys.getenv("LOCALAPPDATA"), "Programs/Python/Python312/python.exe"), unname(Sys.which("python3")), unname(Sys.which("python")))
  } else {
    configured <- Sys.getenv(paste0("BROHN_PYTHON_", toupper(gsub("-", "_", profile))), "")
    candidates <- if (nzchar(configured)) configured else file.path(project, "../../work/tooling", paste0(profile, "-venv"), if (.Platform$OS.type == "windows") "Scripts/python.exe" else "bin/python")
  }
  available <- candidates[nzchar(candidates) & file.exists(candidates) & !dir.exists(candidates)]
  list(configured = nzchar(configured), path = if (length(available)) normalizePath(available[[1]], winslash = "/", mustWork = TRUE) else NULL,
    attempted = as.list(candidates))
}

brohn_doctor_python <- function(profile, project, required = FALSE) {
  selected <- brohn_doctor_python_path(profile, project)
  base <- c(list(profile = profile, required = required), selected)
  if (is.null(selected$path)) return(c(base, list(status = "missing", message = "Configure this profile's explicit Python executable; no alternative profile is used.")))
  if (!requireNamespace("processx", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE)) return(c(base,
    list(status = "not_checked", message = "Restore core R processx and jsonlite before supervised Python inspection.")))
  tryCatch({
    run <- processx::run(selected$path, c("-B", file.path(project, "scripts/check-scientific-runtime.py"), "--profile", profile, "--root", project),
      timeout = 180, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
    if (nchar(run$stdout, type = "bytes") > 1024^2) stop("Runtime check exceeded its 1 MiB output bound.")
    detail <- jsonlite::fromJSON(trimws(run$stdout), simplifyVector = FALSE)
    if (!identical(detail$schema, "brohn-scientific-runtime-check/1.0") || !identical(detail$profile, profile)) stop("Unexpected runtime check response.")
    c(base, list(status = if (run$status == 0L && identical(detail$status, "ready")) "ready" else "not_ready", detail = detail))
  }, error = function(e) c(base, list(status = "not_ready", message = substr(conditionMessage(e), 1, 2000))))
}

brohn_doctor_codec <- function(name, required = FALSE) {
  path <- unname(Sys.which(name)); item <- list(name = name, required = required, path = if (nzchar(path)) path else NULL, status = "missing")
  if (!nzchar(path)) {item$message <- "Add the selected codec executable directory to PATH before launching Brohn."; return(item)}
  if (!requireNamespace("processx", quietly = TRUE)) {item$status <- "not_checked"; return(item)}
  tryCatch({
    run <- processx::run(path, "-version", timeout = 15, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
    version <- strsplit(run$stdout, "\n", fixed = TRUE)[[1]][[1]]
    item$version <- substr(version, 1, 1000)
    item$status <- if (run$status == 0L && startsWith(version, paste(name, "version"))) "ready" else "not_ready"
    item
  }, error = function(e) {item$status <- "not_ready"; item$message <- conditionMessage(e); item})
}

brohn_doctor_publication <- function(project, core_ready = TRUE) {
  if (!isTRUE(core_ready)) return(list(status="not_checked",required=TRUE,ready=FALSE,message="Restore the core R installation before checking report publication."))
  tryCatch({
    previous<-getwd();on.exit(setwd(previous),add=TRUE);setwd(project)
    scope<-new.env(parent=baseenv())
    for (module in c("core","publication")) sys.source(file.path("R",paste0("platform-",module,".R")),envir=scope)
    result<-scope$brohn_publication_readiness()
    c(list(status=if(isTRUE(result$ready))"ready"else"not_ready",required=TRUE),result)
  },error=function(e)list(status="not_ready",required=TRUE,ready=FALSE,message=conditionMessage(e)))
}

brohn_doctor <- function(project, library, profiles = .brohn_doctor_profiles, required_profiles = character(), require_portability = FALSE, require_ffprobe = FALSE) {
  if (!all(c(profiles, required_profiles) %in% .brohn_doctor_profiles)) stop("Unknown scientific profile.", call. = FALSE)
  core <- brohn_doctor_core(project, library)
  # Keep child-control namespaces and libraries pinned after the core inspection.
  prior <- .libPaths(); on.exit(.libPaths(prior), add = TRUE)
  if (dir.exists(library)) .libPaths(c(library, .Library), include.site = FALSE)
  selected <- unique(c(profiles, required_profiles))
  scientific <- lapply(selected, function(profile) brohn_doctor_python(profile, project, profile %in% required_profiles))
  portability <- brohn_doctor_python("portability", project, require_portability)
  codec <- brohn_doctor_codec("ffprobe", require_ffprobe)
  publication <- brohn_doctor_publication(project,identical(core$status,"ready"))
  required <- c(list(core,publication), Filter(function(p) p$required, c(scientific, list(portability, codec))))
  list(schema = "brohn-local-doctor/1.0", status = if (all(vapply(required, function(p) p$status == "ready", logical(1)))) "ready" else "not_ready",
    checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), platform = R.version$platform,
    project = normalizePath(project, winslash = "/", mustWork = TRUE), core = core, portability = portability,
    scientific = scientific, ffprobe = codec, publication = publication,
    limitations = list("Readiness verifies installed runtime dependencies and pinned model assets, not scientific accuracy, physical device qualification or human usability.",
      "The exercised native installation is Windows AMD64 with R 4.6.1 and Python 3.12; other platform restores need their own evidence.",
      "Missing optional profiles do not block core study, questionnaire, gaze and task workflows; their analysis and media capabilities remain unavailable.",
      "No package restore, model download, camera/microphone activation, device discovery or workspace database mutation is performed."))
}

brohn_doctor_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  usage <- "Usage: Rscript --vanilla scripts/doctor.R [--library PATH] [--json] [--profiles methods,acquisition,vision-audio,segmentation|none] [--required-profiles LIST] [--require-portability] [--require-ffprobe]"
  if ("--help" %in% args) {cat(usage, "\n"); return(0L)}
  file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]])
  project <- normalizePath(file.path(dirname(file), ".."), winslash = "/", mustWork = TRUE)
  library <- if (dir.exists(file.path(project, "renv/library"))) file.path(project, "renv/library") else .libPaths()[[1L]]
  json <- FALSE; profiles <- .brohn_doctor_profiles; required <- character(); portability <- FALSE; ffprobe <- FALSE
  i <- 1L
  while (i <= length(args)) {
    flag <- args[[i]]
    if (flag %in% c("--library", "--profiles", "--required-profiles")) {
      if (i == length(args)) stop(usage, call. = FALSE)
      value <- args[[i+1L]]; i <- i+1L
      if (flag == "--library") library <- value else {
        parsed <- if (value == "none") character() else unique(strsplit(value, ",", fixed = TRUE)[[1]])
        if (!length(parsed) && value != "none" || !all(parsed %in% .brohn_doctor_profiles)) stop(usage, call. = FALSE)
        if (flag == "--profiles") profiles <- parsed else required <- parsed
      }
    } else if (flag == "--json") json <- TRUE else if (flag == "--require-portability") portability <- TRUE else if (flag == "--require-ffprobe") ffprobe <- TRUE else stop(usage, call. = FALSE)
    i <- i+1L
  }
  result <- brohn_doctor(project, library, profiles, required, portability, ffprobe)
  if (json) cat(brohn_doctor_json(result), "\n", sep = "") else {
    cat("Brohn local readiness: ", result$status, "\n", sep = "")
    cat("Core R: ", result$core$status, " (", result$core$library, ")\n", sep = "")
    if (!is.null(result$core$message)) cat(result$core$message, "\n")
    cat("Report publication: ", result$publication$status, " [required]\n", sep="")
    if (!is.null(result$publication$message)) cat(result$publication$message,"\n")
    if (!is.null(result$publication$action)) cat(result$publication$action,"\n")
    for (p in c(list(result$portability), result$scientific)) cat(p$profile, ": ", p$status, if (p$required) " [required]" else " [optional]", "\n", sep = "")
    cat("ffprobe: ", result$ffprobe$status, if (result$ffprobe$required) " [required]" else " [optional]", "\n", sep = "")
    cat("Use --json for package versions, import failures, model hashes and executable paths. No installation or device operation was performed.\n")
  }
  if (result$status == "ready") 0L else 1L
}

if (sys.nframe() == 0L) quit(status = brohn_doctor_main())
