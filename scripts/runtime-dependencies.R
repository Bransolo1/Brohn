# Direct dependencies of the connected local profile. renv.lock includes their
# full transitive closure. Optional scientific runtimes are separate profiles.
brohn_runtime_packages <- c("shiny", "bslib", "jsonlite", "png", "digest", "DBI",
  "RSQLite", "processx", "ps", "openssl", "zip", "httpuv", "later", "htmltools")
brohn_require_runtime <- function(project = getwd(), library = .libPaths()[[1L]]) {
  # Reuse the read-only core and required publication checks; startup does not
  # probe optional scientific profiles, codecs, models or devices. Fallback can hide a broken
  # installation, so all services inherit this one verified library closure.
  source(file.path(project, "scripts/doctor.R"), local = TRUE, encoding = "UTF-8")
  readiness <- brohn_doctor_core(project, library)
  if (!identical(readiness$status, "ready")) {
    problems <- Filter(function(p) p$status != "ready", readiness$packages)
    detail <- if (length(problems)) paste(vapply(problems, `[[`, character(1), "name"), collapse = ", ") else
      if (!is.null(readiness$expected_r_version) && !isTRUE(readiness$r_matches)) paste("R", readiness$expected_r_version, "is required") else readiness$message
    stop("Brohn's selected R installation needs attention: ", detail,
      ". Run scripts/doctor.R --library PATH and restore renv.lock; see docs/operations/LOCAL-INSTALLATION.md.", call. = FALSE)
  }
  .libPaths(c(normalizePath(library, winslash = "/", mustWork = TRUE), .Library), include.site = FALSE)
  publication<-brohn_doctor_publication(project)
  if(!isTRUE(publication$ready)) stop("Brohn's report publisher needs attention: ",publication$message," ",publication$action,
    " See docs/operations/LOCAL-INSTALLATION.md.",call.=FALSE)
  invisible(TRUE)
}
