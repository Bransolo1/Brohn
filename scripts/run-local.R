# Historical prototype, retained for old-reader verification and migration.
Sys.setenv(BROHN_APP_MODE = "legacy")
packages <- c("jsonlite", "shiny", "bslib", "png", "digest")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop(paste("Install these R packages first:", paste(missing, collapse = ", ")), call. = FALSE)
options(shiny.maxRequestSize = 16 * 1024 * 1024)
port <- suppressWarnings(as.integer(Sys.getenv("RESEARCH_PLATFORM_PORT", "3838")))
if (is.na(port) || port < 1024 || port > 65535) stop("Use a port between 1024 and 65535.", call. = FALSE)
message("Open http://127.0.0.1:", port, " in your browser. Stop with Ctrl+C.")
shiny::runApp(".", host = "127.0.0.1", port = port, launch.browser = FALSE)
