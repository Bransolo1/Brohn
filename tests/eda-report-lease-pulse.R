# Deterministic lease component regression. No worker, service, source hydration,
# native guard or scientific computation is executed. Uses real SQLite job APIs
# and the exact pulse-installation expression from brohn_process_job, evaluated
# in a private environment with a shared injected wall/store clock.
# Rscript tests/eda-report-lease-pulse.R <repo> <fresh-output>
# During integration: <baseline-repo> <root-candidate> <fresh-output>
args <- commandArgs(TRUE)
stopifnot(length(args) %in% c(2L, 3L))
test_path <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]),
  winslash = "/", mustWork = TRUE)
repo <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
candidate <- normalizePath(if (length(args) == 3L) args[[2L]] else repo,
  winslash = "/", mustWork = TRUE)
out <- args[[length(args)]]
stopifnot(!file.exists(out), dir.create(out, recursive = TRUE))
out <- normalizePath(out, winslash = "/", mustWork = TRUE)
setwd(repo)
source_paths <- c(file.path(repo, c("R/platform-core.R", "R/platform-store.R", "R/platform-publication.R")),
  file.path(candidate, "R/platform-jobs.R"))
source_hashes <- vapply(source_paths, function(p) digest::digest(file = p, algo = "sha256"), character(1))
e <- new.env(parent = globalenv())
for (p in c("R/platform-core.R", "R/platform-store.R", "R/platform-publication.R"))
  sys.source(file.path(repo, p), envir = e, keep.source = FALSE)
clock <- new.env(parent = emptyenv()); clock$now <- 1000000000
e$Sys.time <- function() as.POSIXct(clock$now, origin = "1970-01-01", tz = "UTC")
e$.brohn_store_now <- function() clock$now
parsed <- parse(file.path(candidate, "R/platform-jobs.R"), keep.source = FALSE)
definition <- Filter(function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
  identical(x[[2L]], as.name("brohn_process_job")), as.list(parsed))
stopifnot(length(definition) == 1L)
process <- eval(definition[[1L]][[3L]], envir = e)
matches <- list()
walk <- function(x) {
  if (!is.call(x)) return(invisible(NULL))
  if (identical(x[[1L]], as.name("if")) &&
      grepl("controlled-task-choice-eda-report-package/0.1", paste(deparse(x[[2L]]), collapse = ""), fixed = TRUE) &&
      grepl("lease_checkpoint <-", paste(deparse(x[[3L]]), collapse = ""), fixed = TRUE))
    matches[[length(matches) + 1L]] <<- x
  for (i in seq_along(x)) if (is.call(x[[i]])) walk(x[[i]])
}
walk(body(process)); stopifnot(length(matches) == 1L)
pulse_expression <- matches[[1L]]
writeLines(deparse(pulse_expression, width.cutoff = 120L), file.path(out, "executed-pulse-expression.R"))
checks <- list(); errors <- list(); stores <- list()
check <- function(name, value) {
  checks[[length(checks) + 1L]] <<- list(name = name, passed = isTRUE(value))
  cat(if (isTRUE(value)) "PASS" else "FAIL", name, "\n")
  if (!isTRUE(value)) stop(name, call. = FALSE)
}
rejected <- function(name, expr, text = NULL) {
  result <- tryCatch({force(expr); NULL}, error = identity)
  errors[[name]] <<- if (inherits(result, "error")) conditionMessage(result) else NULL
  inherits(result, "error") && (is.null(text) || grepl(text, conditionMessage(result), fixed = TRUE))
}
new_case <- function(name, operation = "eda_display", profile = "controlled-task-choice-eda-report-package/0.1",
                     timeout = 300, deadline = 300) {
  clock$now <- clock$now + 1000
  s <- e$brohn_open_store(file.path(out, name)); stores[[name]] <<- s
  queued <- e$brohn_enqueue_job(s, operation, list(limits = list(profile = profile), original = name), name)
  j <- e$brohn_claim_job(s, "owner", 60)
  stopifnot(identical(j$id, queued$id), j$lease_until == clock$now + 60)
  local <- new.env(parent = e)
  local$store <- s; local$job <- j; local$started <- clock$now
  local$profile <- list(deadline_seconds = deadline); local$timeout_seconds <- timeout
  local$pulse <- NULL
  eval(pulse_expression, envir = local)
  list(store = s, job = j, pulse = local$pulse, env = local, start = clock$now)
}
row <- function(x) e$brohn_get_job(x$store, x$job$id)
audit <- function(x) DBI::dbGetQuery(x$store$con,
  "SELECT action,detail_json FROM audit_log WHERE target=? ORDER BY sequence", params = list(x$job$id))
snapshot <- function(x) list(job = row(x), audit = audit(x))
fail <- function(x) e$brohn_fail_job(x$store, x$job$id, x$job$worker, x$job$token,
  list(message = "Fixture failure", source_preserved = TRUE))
complete <- function(x) e$brohn_complete_job(x$store, x$job$id, x$job$worker, x$job$token,
  list(fixture = TRUE))

# Parent preparation, a short child and long parent validation share one clock.
x <- new_case("long-parent")
check("new EDA preparation installs the exact callback", is.function(x$pulse))
for (offset in c(14.9, 15, 29.9, 30, 44.9, 45, 59.9, 60, 61, 74.9, 75, 90, 105, 120)) {
  clock$now <- x$start + offset; x$pulse()
  check(paste("original attempt remains live at", offset),
    row(x)$attempt == 1L && row(x)$lease_until > clock$now && is.null(e$brohn_claim_job(x$store, "other", 60)))
}
check("renewal cadence spans parent phases without resetting at the short child",
  sum(audit(x)$action == "job.renewed") == 8L && row(x)$lease_until == x$start + 180)
check("unchanged publication fence accepts the same live original attempt",
  identical(e$.brohn_publication_job(x$store, x$job)$token, x$job$token))
invisible(complete(x))
check("one long attempt completes without a reclaim", row(x)$status == "succeeded" &&
  sum(audit(x)$action == "job.claimed") == 1L)
before <- snapshot(x)
check("completed work cannot be renewed", rejected("completed", x$pulse(), "original job lease") &&
  identical(before, snapshot(x)))

x <- new_case("cancel-before-cadence")
clock$now <- x$start + .1; invisible(e$brohn_cancel_job(x$store, x$job$id)); before <- snapshot(x)
check("forced check notices cancellation even before the old quarter-second check cadence",
  rejected("cancelled", x$pulse(), "original job lease") && identical(before, snapshot(x)))
check("cancelled output and failure cannot overwrite the terminal cancellation",
  rejected("cancelled-success", complete(x)) && rejected("cancelled-failure", fail(x)) &&
  identical(before, snapshot(x)))
retry <- e$brohn_enqueue_job(x$store, "eda_display", x$job$request, "explicit-retry")
retried <- e$brohn_claim_job(x$store, "retry-owner", 60)
check("an explicit retry is a new job while the cancelled identity remains cancelled",
  identical(retry$id, retried$id) && !identical(retry$id, x$job$id) && row(x)$status == "cancelled")
invisible(e$brohn_fail_job(x$store, retried$id, retried$worker, retried$token, list(message = "fixture terminal")))

x <- new_case("expiry-boundary")
clock$now <- x$start + 60; before <- snapshot(x)
check("exact expiry refuses before renewal and cannot revive the original lease",
  rejected("expired", x$pulse(), "original job lease") && identical(before, snapshot(x)))
check("direct store renewal also refuses the expired lease",
  rejected("expired-renew", e$brohn_renew_job(x$store, x$job$id, x$job$worker, x$job$token, 60)) &&
  identical(before, snapshot(x)))
check("expired owner cannot publish success or record a terminal failure",
  rejected("expired-success", complete(x)) && rejected("expired-failure", fail(x)) && identical(before, snapshot(x)))
successor <- e$brohn_claim_job(x$store, "replacement", 60); before <- snapshot(x)
check("expired work is reclaimable only through a new fenced attempt",
  successor$attempt == 2L && successor$token != x$job$token && successor$worker == "replacement")
check("old callback cannot renew a live replacement attempt",
  rejected("replaced", x$pulse(), "original job lease") && identical(before, snapshot(x)))
check("old completion and failure cannot overwrite the live replacement",
  rejected("replaced-success", complete(x)) && rejected("replaced-failure", fail(x)) && identical(before, snapshot(x)))
invisible(e$brohn_complete_job(x$store, successor$id, successor$worker, successor$token, list(replacement = TRUE)))
check("the valid replacement retains its own result", isTRUE(row(x)$result$replacement))

# Request and attempt are part of the publication fence even if token/worker match.
for (field in c("request", "attempt", "worker", "token")) {
  x <- new_case(paste0("guard-", field)); before <- snapshot(x)
  if (field == "request") x$env$job$request$original <- "changed"
  else if (field == "attempt") x$env$job$attempt <- x$job$attempt + 1L
  else x$env$job[[field]] <- "wrong"
  check(paste("original", field, "binding remains fenced"),
    rejected(paste0("guard-", field), e$.brohn_publication_job(x$store, x$env$job), "original job lease") && identical(before, snapshot(x)))
  clock$now <- x$start + 15; x$pulse()
  check(paste("checkpoint retains its captured original job despite caller-local", field, "mutation"),
    identical(row(x)$request, x$job$request) && row(x)$worker == x$job$worker &&
    row(x)$token == x$job$token && row(x)$attempt == x$job$attempt &&
    sum(audit(x)$action == "job.renewed") == 1L)
  invisible(fail(x))
}

for (kind in c("profile", "caller")) {
  x <- new_case(paste0("deadline-", kind), timeout = if (kind == "caller") 45 else 300,
    deadline = if (kind == "profile") 45 else 300)
  for (offset in c(15, 30, 45)) {clock$now <- x$start + offset; x$pulse()}
  check(paste(kind, "deadline permits its exact boundary without moving the original start"),
    identical(x$env$started, x$start) && row(x)$lease_until == x$start + 105)
  clock$now <- x$start + 45.001; before <- snapshot(x)
  check(paste(kind, "deadline refuses despite a valid renewed lease"),
    rejected(paste0("deadline-", kind), x$pulse(), "declared time limit") && identical(before, snapshot(x)))
  invisible(fail(x))
  check(paste(kind, "deadline failure is recordable by the still-valid owner"),
    row(x)$status == "failed" && isTRUE(row(x)$error$source_preserved))
}
x <- new_case("publish-profile", operation = "report_package")
check("new EDA report profile installs the same pulse", is.function(x$pulse)); invisible(fail(x))
for (case in list(c("task_display", "controlled-task-report-package/0.1"),
                 c("choice_display", "controlled-task-choice-report-package/0.1"),
                 c("report_package", "controlled-task-choice-report-package/0.1"),
                 c("report_package", "controlled-report-package/0.1"),
                 c("clock_plot", "not-applicable"))) {
  x <- new_case(paste0("legacy-", length(stores)), operation = case[[1L]], profile = case[[2L]])
  check(paste("existing route retains its old renewal behavior:", paste(case, collapse = "/")),
    is.null(x$pulse) && sum(audit(x)$action == "job.renewed") == 0L)
  invisible(fail(x))
}
check("no source, entity or artifact was published by this component test",
  all(vapply(stores, function(s) all(vapply(c("entities", "entity_versions", "objects"),
    function(table) DBI::dbGetQuery(s$con, paste("SELECT COUNT(*) AS n FROM", table))$n == 0L,
    logical(1))), logical(1))))
identities <- lapply(c("R/platform-core.R", "R/platform-store.R", "R/platform-publication.R", "R/platform-jobs.R"),
  function(p) list(path = p, sha256 = digest::digest(file = file.path(if (p == "R/platform-jobs.R") candidate else repo, p), algo = "sha256")))
check("all loaded source files remain byte-identical", identical(source_hashes,
  vapply(source_paths, function(p) digest::digest(file = p, algo = "sha256"), character(1))))
for (s in stores) e$brohn_close_store(s)
receipt <- list(schema = "brohn-eda-lease-pulse-component/0.1", passed = TRUE,
  checks = checks, check_count = length(checks), source_files = identities,
  pulse_expression_sha256 = digest::digest(file = file.path(out, "executed-pulse-expression.R"), algo = "sha256"),
  test_sha256 = digest::digest(file = test_path, algo = "sha256"),
  errors = errors,
  scope = "Real SQLite lease/cancel/finish APIs; exact private pulse expression; injected coherent clock; no child, native source guards, source reads, scientific work or integrated publication")
writeBin(charToRaw(enc2utf8(e$brohn_json(receipt, pretty = TRUE))), file.path(out, "results.json"))
cat("PASS", length(checks), "lease pulse component checks\n")
