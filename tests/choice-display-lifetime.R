# Real unchanged choice child. Parent poll/release instrumentation only.
# Cancellation uses the normal API; lease replacement uses the normal claim API
# under a declared temporary test clock. No source or child code is edited.
# Rscript tests/choice-display-lifetime.R <checkout> <generated-originals> <fresh-evidence>
args <- commandArgs(TRUE); stopifnot(length(args) == 3L)
root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
original <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
out <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
stopifnot(!file.exists(out), dir.exists(file.path(original, "workspace")), file.exists(file.path(original, "native-report.json")))
receipt <- jsonlite::fromJSON(file.path(original, "results.json"), simplifyVector = FALSE)
stopifnot(isTRUE(receipt$passed))
dir.create(out, recursive = TRUE)
stopifnot(file.copy(file.path(original, "workspace"), out, recursive = TRUE, copy.mode = TRUE, copy.date = TRUE))
stopifnot(file.copy(file.path(original, "native-report.json"), file.path(out, "native-report.json")))
cfg <- list(checkout = root, out = out)
jsonlite::write_json(list(schema = "brohn-choice-lifetime-portable/0.1", checkout = root, source_originals = original,
  original_receipt_sha256 = digest::digest(file = file.path(original, "results.json"), algo = "sha256")), file.path(out, "config.json"), auto_unbox = TRUE, pretty = TRUE)
setwd(cfg$checkout); source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
local({
  store <- brohn_open_store(file.path(cfg$out, "workspace"))
  checks <- list(); traces <- list(); failure <- NULL; passed <- FALSE
  real_get <- brohn_get_job; real_release <- brohn_release_choice_display_sources; real_now <- .brohn_store_now
  before_jobs <- DBI::dbGetQuery(store$con, "SELECT * FROM jobs ORDER BY rowid")
  before_versions <- DBI::dbGetQuery(store$con, "SELECT * FROM entity_versions ORDER BY rowid")
  before_objects <- DBI::dbGetQuery(store$con, "SELECT * FROM objects ORDER BY hash")
  check <- function(name, value) {
    if (!isTRUE(value)) stop(name, call. = FALSE)
    checks[[length(checks) + 1L]] <<- name; cat("PASS", name, "\n")
  }
  restore <- function() {
    assign("brohn_get_job", real_get, envir = .GlobalEnv)
    assign("brohn_release_choice_display_sources", real_release, envir = .GlobalEnv)
    assign(".brohn_store_now", real_now, envir = .GlobalEnv)
  }
  on.exit({
    restore()
    for (j in brohn_list_jobs(store, limit = 100L)) if (j$status %in% c("queued", "running")) brohn_cancel_job(store, j$id)
    brohn_write_json_file(list(schema = "brohn-choice-child-lifetime-checks/0.1", passed = passed, checks = checks,
      failure = failure, traces = traces,
      scope = "Real unchanged native choice child and source seals. The parent first-poll wrapper injects normal API cancellation or normal reclaim with a temporary test clock, then delegates every read. The release wrapper observes child exit and still-live guards before delegating release. No real hosted user, wall-clock expiry, physical participant or successful new preparation is claimed."), file.path(cfg$out, "results.json"))
    brohn_close_store(store)
  }, add = TRUE)
  tryCatch({
    original <- brohn_read_json_file(file.path(cfg$out, "native-report.json")); ref <- .brohn_rpk_ref(original)
    for (mode in c("cancel", "replace")) {
      queued <- brohn_queue_choice_display(store, ref, retry = TRUE)
      job <- brohn_claim_job(store, paste0("choice-child-original-", mode), lease_seconds = 120L)
      stopifnot(identical(job$id, queued$id))
      observation <- new.env(parent = emptyenv()); observation$injected <- FALSE; observation$release <- NULL
      parent_frame <- function() {
        frames <- Filter(function(e) exists("child", envir = e, inherits = FALSE) && exists("job", envir = e, inherits = FALSE) && exists("scratch", envir = e, inherits = FALSE), sys.frames())
        if (!length(frames)) return(NULL)
        frames[[length(frames)]]
      }
      assign("brohn_get_job", function(current_store, id) {
        current <- real_get(current_store, id)
        frame <- parent_frame()
        if (!observation$injected && identical(id, job$id) && !is.null(frame)) {
          child <- get("child", envir = frame, inherits = FALSE)
          if (!is.null(child) && child$is_alive()) {
            observation$injected <- TRUE
            observation$child_pid <- child$get_pid()
            observation$child_alive_when_injected <- TRUE
            observation$scratch <- get("scratch", envir = frame, inherits = FALSE)
            if (mode == "cancel") {
              brohn_cancel_job(current_store, id)
            } else {
              expiry <- current$lease_until + 1
              assign(".brohn_store_now", function() expiry, envir = .GlobalEnv)
              replacement <- tryCatch(brohn_claim_job(current_store, "choice-child-replacement", lease_seconds = 120L),
                finally = assign(".brohn_store_now", real_now, envir = .GlobalEnv))
              stopifnot(identical(replacement$id, job$id), replacement$attempt == job$attempt + 1L, !identical(replacement$token, job$token))
              observation$replacement <- replacement
            }
            current <- real_get(current_store, id)
          }
        }
        current
      }, envir = .GlobalEnv)
      assign("brohn_release_choice_display_sources", function(handle) {
        frame <- parent_frame()
        child <- if (is.null(frame)) NULL else get("child", envir = frame, inherits = FALSE)
        live_guards <- tryCatch({.brohn_cm_guard_check(c(handle$guards, handle$state$extra_guards)); TRUE}, error = function(e) FALSE)
        observed <- list(child_observed = !is.null(child), child_alive_before_release = if (is.null(child)) NULL else child$is_alive(),
          child_pid = if (is.null(child)) NULL else child$get_pid(), source_handle_open = !isTRUE(handle$state$closed),
          guarded_sources = length(handle$guards), guarded_native_and_bundle_files = length(handle$state$extra_guards),
          guards_alive_before_release = live_guards)
        real_release(handle)
        observed$source_handle_closed_after_release <- isTRUE(handle$state$closed)
        observation$release <- observed
        invisible(NULL)
      }, envir = .GlobalEnv)
      tryCatch(brohn_process_job(store, job, timeout_seconds = 240L), finally = restore())
      current <- real_get(store, job$id)
      traces[[mode]] <- as.list(observation)
      check(paste(mode, "was injected only after a real child was observed alive"), isTRUE(observation$injected) && isTRUE(observation$child_alive_when_injected))
      release <- observation$release
      check(paste(mode, "child stopped before all source guards were released"), isTRUE(release$child_observed) && identical(release$child_pid, observation$child_pid) && identical(release$child_alive_before_release, FALSE) && isTRUE(release$guards_alive_before_release) && release$guarded_sources > 0L && release$guarded_native_and_bundle_files >= 3L)
      check(paste(mode, "source handle closed and owned scratch removed after release"), isTRUE(release$source_handle_open) && isTRUE(release$source_handle_closed_after_release) && !dir.exists(observation$scratch))
      if (mode == "cancel") {
        check("cancelled attempt stays cancelled with no publication result", current$status == "cancelled" && is.null(current$result))
      } else {
        check("obsolete child cannot overwrite the new running lease", current$status == "running" && current$attempt == observation$replacement$attempt && identical(current$token, observation$replacement$token) && is.null(current$result) && is.null(current$error))
      }
      denied <- tryCatch({brohn_publish_choice_display(store, NULL, cfg$out, job, NULL, "never-read.json"); NULL}, error = function(e) conditionMessage(e))
      check(paste(mode, "obsolete direct publication refuses at its lease fence before artifact access"), !is.null(denied) && grepl("original job lease", denied, fixed = TRUE))
      traces[[mode]]$publication_refusal <- denied
      if (current$status == "running") brohn_cancel_job(store, current$id)
      check(paste(mode, "publishes no choice display or stored object"), DBI::dbGetQuery(store$con, "SELECT COUNT(*) n FROM entities WHERE kind='choice_display'")$n[[1L]] == 0L && identical(before_objects, DBI::dbGetQuery(store$con, "SELECT * FROM objects ORDER BY hash")))
    }
    after_jobs <- DBI::dbGetQuery(store$con, "SELECT * FROM jobs ORDER BY rowid")
    check("all original scientific jobs remain exact", identical(before_jobs, after_jobs[match(before_jobs$id, after_jobs$id), , drop = FALSE]))
    check("all original source entity versions remain exact", identical(before_versions, DBI::dbGetQuery(store$con, "SELECT * FROM entity_versions ORDER BY rowid")))
    check("all original object bytes remain exact", all(vapply(before_objects$hash, function(h) identical(digest::digest(file = brohn_object_path(store, h, FALSE), algo = "sha256"), h), logical(1))))
    passed <- TRUE
  }, error = function(e) { failure <<- conditionMessage(e); stop(e) })
  cat(length(checks), "choice child lifetime checks passed\n")
})
