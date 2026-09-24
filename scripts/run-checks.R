# Run allowlisted, isolated R checks with a durable per-test result and logs.
# This never runs the saved-workspace browser journeys against a research store.
arguments <- commandArgs(trailingOnly = TRUE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
project <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
usage <- "Usage: Rscript --vanilla scripts/run-checks.R --list | (--suite domain|scientific|operations|interchange | --test ID) [--output EXTERNAL_DIRECTORY]"
options <- list(); i <- 1L
while (i <= length(arguments)) {
  flag <- arguments[[i]]
  if (flag == "--list") {options$list <- TRUE; i <- i + 1L; next}
  if (!flag %in% c("--suite", "--test", "--output") || i == length(arguments)) stop(usage, call. = FALSE)
  key <- substring(flag, 3L)
  if (!is.null(options[[key]])) stop("Specify each option once. ", usage, call. = FALSE)
  options[[key]] <- arguments[[i + 1L]]; i <- i + 2L
}
source(file.path(project, "scripts/runtime-dependencies.R"), local = TRUE)
brohn_require_runtime(project)
catalog <- jsonlite::fromJSON(file.path(project, "scripts/qa-catalog.json"), simplifyVector = FALSE)
stopifnot(identical(catalog$schema, "brohn-qa-catalog/1.0"))
if (isTRUE(options$list)) {
  if (length(options) != 1L) stop("Use --list on its own.", call. = FALSE)
  for (test in catalog$tests) cat(sprintf("%-24s %-12s %s\n", test$id, test$suite, test$path))
  cat("\n", catalog$scope, "\n", sep = ""); quit(status = 0L)
}
if (sum(!vapply(options[c("suite", "test")], is.null, logical(1))) != 1L) stop(usage, call. = FALSE)
selected <- Filter(function(test) if (!is.null(options$test)) identical(test$id, options$test) else identical(test$suite, options$suite), catalog$tests)
if (!length(selected)) stop("No registered checks match. Use --list for the supported selections.", call. = FALSE)
output <- if (is.null(options$output)) tempfile("brohn-qa-") else path.expand(options$output)
if (!grepl("^([A-Za-z]:[/\\\\]|[/\\\\])", output)) output <- file.path(getwd(), output)
output <- normalizePath(output, winslash = "/", mustWork = FALSE)
if (identical(tolower(output), tolower(project)) || startsWith(tolower(output), paste0(tolower(project), "/")))
  stop("Choose a QA output directory outside the source repository.", call. = FALSE)
if (file.exists(file.path(output, "results.json"))) stop("This QA directory already contains results. Choose a new run directory.", call. = FALSE)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(output, winslash = "/", mustWork = TRUE)
if (identical(tolower(output), tolower(project)) || startsWith(tolower(output), paste0(tolower(project), "/")))
  stop("The resolved QA directory is inside the source repository. Choose an external directory.", call. = FALSE)
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
implementation_hashes <- function() {
  folders <- c("R", "src", "scripts", "scripts/workers", "scripts/acquisition", "www", "www/participant")
  paths <- unique(c(unlist(lapply(folders, function(folder) file.path(folder,
    list.files(file.path(project, folder), pattern = "\\.(R|py|js|mjs|css|json|c|h|ps1)$", recursive = FALSE))), use.names = FALSE), "renv.lock"))
  paths <- sort(paths[file.exists(file.path(project, paths)) & !dir.exists(file.path(project, paths))])
  stats::setNames(lapply(paths, function(path) digest::digest(file = file.path(project, path), algo = "sha256")), paths)
}
code_identity <- implementation_hashes()
manifest <- list(schema = "brohn-qa-run/1.0", scope = catalog$scope, started_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  catalog_hash = digest::digest(file = file.path(project, "scripts/qa-catalog.json"), algo = "sha256"),
  r_version = as.character(getRversion()), library = .libPaths()[1L], implementation_hashes = code_identity,
  selected = lapply(selected, `[[`, "id"), results = list(), status = "running")
save_results <- function() writeLines(enc2utf8(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null")), file.path(output, "results.json"), useBytes = TRUE)
save_results(); cat("QA results: ", output, "\n", sep = "")
for (test in selected) {
  stdout <- file.path(output, paste0(test$id, "-stdout.log")); stderr <- file.path(output, paste0(test$id, "-stderr.log"))
  started <- Sys.time(); cat("RUN ", test$id, "\n", sep = ""); flush.console()
  test_path <- normalizePath(file.path(project, test$path), winslash = "/", mustWork = TRUE)
  stopifnot(startsWith(test_path, paste0(project, "/tests/")), grepl("^[a-z0-9-]+$", test$id))
  source_hash <- digest::digest(file = test_path, algo = "sha256")
  # Keep retained worker paths short on Windows. The receipt retains the full
  # test identity; this ordinal is only an address within this unique run.
  test_index <- match(test$id, vapply(selected, `[[`, character(1), "id"))
  evidence_parent <- file.path(output, "e", sprintf("%03d", test_index))
  if (file.exists(evidence_parent)) stop("The selected test evidence directory already exists; choose a fresh run directory.", call. = FALSE)
  dir.create(evidence_parent, recursive = TRUE, showWarnings = FALSE)
  evidence_parent <- normalizePath(evidence_parent, winslash = "/", mustWork = TRUE)
  stopifnot(startsWith(tolower(evidence_parent), paste0(tolower(output), "/")))
  outcome <- tryCatch(processx::run(rscript, c("--vanilla", test$path), wd = project, timeout = test$timeout_s,
    stdout = stdout, stderr = stderr, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE,
    env = c("current", R_LIBS_USER = .libPaths()[1L], BROHN_QA_EVIDENCE_PARENT = evidence_parent)), error = function(e) list(status = NULL, error = conditionMessage(e)))
  unchanged <- identical(source_hash, digest::digest(file = test_path, algo = "sha256")) && identical(code_identity, implementation_hashes())
  passed <- !is.null(outcome$status) && outcome$status == 0L && unchanged
  result <- list(id = test$id, path = test$path, status = if (passed) "passed" else "failed", exit_code = outcome$status,
    error = if (!unchanged) "The check or application source changed during execution; rerun against a stable checkout." else outcome$error,
    duration_s = as.numeric(difftime(Sys.time(), started, units = "secs")), source_hash = source_hash, evidence_parent = evidence_parent,
    stdout = basename(stdout), stderr = basename(stderr))
  manifest$results[[length(manifest$results) + 1L]] <- result; save_results()
  cat(toupper(result$status), " ", test$id, " (", round(result$duration_s, 1), " s)\n", sep = ""); flush.console()
}
manifest$status <- if (all(vapply(manifest$results, function(r) r$status == "passed", logical(1)))) "passed" else "failed"
manifest$finished_at <- format(Sys.time(), tz = "UTC", usetz = TRUE); save_results()
cat("Selected suite: ", manifest$status, ". This does not replace researcher browser or device qualification.\n", sep = "")
quit(status = if (manifest$status == "passed") 0L else 1L)
