# Synthetic, standalone library probes. No application files or participant data.
args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default) {
  pos <- match(name, args)
  if (is.na(pos)) default else args[[pos + 1L]]
}
lib <- normalizePath(arg("--library", "../../work/r-library-platform"), winslash = "/")
.libPaths(c(lib, .libPaths()))
out <- arg("--output", "docs/preparation/platform-results-r.json")
scratch_root <- normalizePath("../../work/tooling/research-web-tools", winslash = "/")
scratch <- tempfile("r-reference-", tmpdir = scratch_root)
dir.create(scratch)
checks <- list()
check <- function(id, actual, expected = TRUE, tolerance = 1e-9, evidence = "synthetic integration probe") {
  ok <- isTRUE(all.equal(actual, expected, tolerance = tolerance, check.attributes = FALSE))
  checks[[length(checks) + 1L]] <<- list(id = id, passed = ok, actual = actual,
    expected = expected, evidence = evidence)
  if (!ok) stop("Failed: ", id)
}
requested <- c("DBI", "RSQLite", "processx", "targets", "crew", "lme4", "emmeans", "psych", "effectsize", "jsonlite")
for (p in requested) stopifnot(requireNamespace(p, quietly = TRUE))

# Same operation + same payload is a replay; a reused operation + changed payload is a conflict.
con <- DBI::dbConnect(RSQLite::SQLite(), file.path(scratch, "journal.sqlite"))
DBI::dbExecute(con, "PRAGMA foreign_keys=ON")
DBI::dbExecute(con, "CREATE TABLE studies (id TEXT PRIMARY KEY)")
DBI::dbExecute(con, paste("CREATE TABLE events (operation_id TEXT PRIMARY KEY, study_id TEXT NOT NULL,",
  "payload TEXT NOT NULL, raw_tick TEXT NOT NULL, FOREIGN KEY (study_id) REFERENCES studies(id))"))
DBI::dbExecute(con, "INSERT INTO studies VALUES ('synthetic-study')")
append_event <- function(id, payload) DBI::dbWithTransaction(con, {
  old <- DBI::dbGetQuery(con, "SELECT payload FROM events WHERE operation_id=?", params = list(id))
  if (nrow(old) && !identical(old$payload[[1]], payload)) stop("idempotence conflict")
  if (!nrow(old)) DBI::dbExecute(con, "INSERT INTO events VALUES (?, ?, ?, ?)",
    params = list(id, "synthetic-study", payload, "9007199254740993"))
  !nrow(old)
})
check("transaction_first_append", append_event("op-1", "A"))
check("idempotent_replay", append_event("op-1", "A"), FALSE)
check("idempotent_count", DBI::dbGetQuery(con, "SELECT count(*) AS n FROM events")$n, 1L)
check("idempotence_conflict_rejected", inherits(try(append_event("op-1", "B"), silent = TRUE), "try-error"))
check("rollback_error", inherits(try(DBI::dbWithTransaction(con, {
  DBI::dbExecute(con, "INSERT INTO events VALUES ('op-2', 'synthetic-study', 'B', '2')")
  stop("injected error")
}), silent = TRUE), "try-error"))
check("rollback_leaves_original_only", DBI::dbGetQuery(con, "SELECT count(*) AS n FROM events")$n, 1L)
check("raw_tick_stays_text", DBI::dbGetQuery(con, "SELECT raw_tick FROM events")$raw_tick, "9007199254740993")
check("foreign_key_rejected", inherits(try(DBI::dbExecute(con,
  "INSERT INTO events VALUES ('orphan', 'absent', 'X', '3')"), silent = TRUE), "try-error"))
DBI::dbDisconnect(con)

# External process captures success and failure; this is not yet a durable product queue.
rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")
worker <- file.path(scratch, "worker.R")
writeLines("cat(sum(c(2, 3, 5)))", worker)
proc <- processx::run(rscript, c("--vanilla", worker), error_on_status = FALSE, timeout = 30000,
  windows_hide_window = TRUE)
check("external_r_process", proc$status == 0L && trimws(proc$stdout) == "10")
writeLines("quit(status = 7)", worker)
proc <- processx::run(rscript, c("--vanilla", worker), error_on_status = FALSE, timeout = 30000,
  windows_hide_window = TRUE)
check("external_failure_status", proc$status, 7L)

# R-owned request, isolated Python worker, typed JSON reply. Files carry synthetic data only.
python <- normalizePath(arg("--python", "../../work/tooling/methods-venv/Scripts/python.exe"), winslash = "/")
request <- list(schema = "brohn-worker-probe/0.1", raw_tick = "9007199254740993",
  unit = "microvolt", missing = NULL, values = c(2, 3, 5))
request_file <- file.path(scratch, "request.json")
jsonlite::write_json(request, request_file, auto_unbox = TRUE, null = "null", digits = 16)
python_worker <- file.path(scratch, "worker.py")
writeLines(c("import json, sys", "with open(sys.argv[1], encoding='utf-8') as stream:",
  "    request = json.load(stream)",
  "assert request['schema'] == 'brohn-worker-probe/0.1'",
  "assert isinstance(request['raw_tick'], str)",
  "assert 'missing' in request and request['missing'] is None",
  "request['total'] = sum(request['values'])", "print(json.dumps(request, allow_nan=False))"), python_worker)
python_proc <- processx::run(python, c(python_worker, request_file), error_on_status = FALSE,
  timeout = 30000, windows_hide_window = TRUE)
check("python_worker_success", python_proc$status, 0L)
reply <- jsonlite::fromJSON(python_proc$stdout, simplifyVector = FALSE)
check("python_decimal_tick_identity", reply$raw_tick, request$raw_tick)
check("python_explicit_null_and_unit", "missing" %in% names(reply) && is.null(reply$missing) &&
  identical(reply$unit, "microvolt"))
check("python_result_arithmetic", reply$total, 10, evidence = "independent arithmetic across R/Python JSON seam")

# A minimal cached analysis graph, separate from both app and benchmark source directory.
target_script <- file.path(scratch, "_targets.R")
target_store <- file.path(scratch, "_targets")
writeLines(c("library(targets)", "list(tar_target(values, c(1, 2, 3)), tar_target(total, sum(values)))"), target_script)
targets::tar_make(script = target_script, store = target_store, callr_function = NULL, reporter = "silent")
check("targets_known_total", targets::tar_read_raw("total", store = target_store), 6)
check("targets_cache_current", length(targets::tar_outdated(script = target_script, store = target_store,
  callr_function = NULL)), 0L)

controller <- crew::crew_controller_local(workers = 1, seconds_idle = 2)
controller$start()
crew_answer <- tryCatch({
  controller$push(name = "synthetic-sum", command = sum(x), data = list(x = c(2, 3, 5)))
  controller$wait(seconds_timeout = 30)
  controller$pop()
}, finally = controller$terminate())
check("crew_local_result", crew_answer$result[[1]], 10)

# Prespecified paired B-A contrast, checked against independent participant differences.
paired <- data.frame(id = factor(rep(1:6, each = 2)),
  condition = factor(rep(c("A", "B"), 6), levels = c("A", "B")),
  y = c(1, 3, 2, 5, 4, 5, 3, 7, 6, 8, 5, 8))
differences <- c(2, 3, 1, 4, 2, 3)
fit <- lm(y ~ id + condition, data = paired)
contrast <- as.data.frame(emmeans::contrast(emmeans::emmeans(fit, ~ condition),
  method = list("B - A" = c(-1, 1)), adjust = "none"))
check("paired_contrast_estimate", contrast$estimate, mean(differences), evidence = "independent arithmetic")
check("paired_contrast_standard_error", contrast$SE, sd(differences) / sqrt(6), evidence = "independent arithmetic")
dz <- as.data.frame(effectsize::cohens_d(paired$y[paired$condition == "B"],
  paired$y[paired$condition == "A"], paired = TRUE))
check("paired_effect_size_dz", dz$Cohens_d, mean(differences) / sd(differences), evidence = "independent arithmetic")
mixed <- lme4::lmer(Reaction ~ Days + (Days | Subject), data = lme4::sleepstudy)
check("lme4_upstream_example_coefficient", unname(lme4::fixef(mixed)[["Days"]]), 10.4672859595969,
  tolerance = 1e-7, evidence = "upstream example replay; not independent empirical validation")
items <- data.frame(q1 = c(1, 2, 2, 4, 5, 3), q2 = c(2, 2, 3, 5, 4, 4), q3 = c(1, 3, 2, 4, 5, 4))
k <- ncol(items)
alpha_expected <- k / (k - 1) * (1 - sum(vapply(items, var, numeric(1))) / var(rowSums(items)))
alpha <- suppressWarnings(psych::alpha(items, check.keys = FALSE, warnings = FALSE))
check("raw_alpha_arithmetic", alpha$total$raw_alpha, alpha_expected, evidence = "independent arithmetic; not scale validation")

installed <- installed.packages(lib.loc = lib)
runtime <- installed.packages(lib.loc = .Library)
manifest <- list(schema = "brohn-platform-r-environment/0.1", r = R.version.string,
  created = as.character(Sys.Date()), binary_repository = "https://cloud.r-project.org/bin/windows/contrib/4.6/",
  runtime_packages = lapply(seq_len(nrow(runtime)), function(i) list(
    package = runtime[i, "Package"], version = runtime[i, "Version"])),
  requested = requested, packages = lapply(seq_len(nrow(installed)), function(i) list(
    package = installed[i, "Package"], version = installed[i, "Version"], license = installed[i, "License"],
    binary_url = paste0("https://cloud.r-project.org/bin/windows/contrib/4.6/", installed[i, "Package"], "_", installed[i, "Version"], ".zip"))))
jsonlite::write_json(manifest, "scripts/readiness/platform-r-packages.json", auto_unbox = TRUE, pretty = TRUE)
result <- list(schema = "brohn-platform-library-probes/0.1", generated = format(Sys.time(), tz = "UTC", usetz = TRUE),
  origin = "synthetic/reference", application_integration = FALSE,
  checks_passed = sum(vapply(checks, function(x) x$passed, logical(1))), checks = checks,
  package_versions = setNames(lapply(requested, function(p) as.character(packageVersion(p))), requested),
  limitations = c("Single-process SQLite probes do not test concurrent writers, migrations, crash recovery or large streams.",
    "Local targets/crew probes are not an implemented durable queue, cancellation, retry policy or Shiny integration.",
    "Statistical arithmetic does not select an analysis design or establish questionnaire validity."))
jsonlite::write_json(result, out, auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null")
cat(length(checks), "platform R checks passed;", nrow(installed), "isolated packages inventoried\n")
