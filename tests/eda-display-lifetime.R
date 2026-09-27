# Real unchanged R worker and Python EDA descendant. Parent instrumentation only.
# Cancellation uses the normal API; lease replacement uses the normal claim API
# under a declared temporary test clock. No source or child code is edited.
# Rscript tests/eda-display-lifetime.R <checkout> <generated-originals> <fresh-evidence> [report-key]
# report-key defaults to continuous-report; corpus04 uses large-report.
args <- commandArgs(TRUE); stopifnot(length(args) %in% c(3L,4L))
root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
original <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
out <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
report_key <- if(length(args)==4L) args[[4L]] else "continuous-report"
stopifnot(grepl("^[a-z][a-z0-9-]{0,79}$",report_key))
report_file <- paste0(report_key,".json")
stopifnot(!file.exists(out), dir.exists(file.path(original, "workspace")), file.exists(file.path(original, report_file)))
receipt <- jsonlite::fromJSON(file.path(original, "results.json"), simplifyVector = FALSE)
stopifnot(isTRUE(receipt$passed))
dir.create(out, recursive = TRUE)
stopifnot(file.copy(file.path(original, "workspace"), out, recursive = TRUE, copy.mode = TRUE, copy.date = TRUE))
stopifnot(file.copy(file.path(original, report_file), file.path(out, report_file)))
cfg <- list(checkout = root, out = out, report_file = report_file)
jsonlite::write_json(list(schema = "brohn-eda-lifetime-portable/0.1", checkout = root, source_originals = original,
  source_report_key = report_key, source_report_sha256 = digest::digest(file=file.path(original,report_file),algo="sha256"),
  original_receipt_sha256 = digest::digest(file = file.path(original, "results.json"), algo = "sha256")), file.path(out, "config.json"), auto_unbox = TRUE, pretty = TRUE)
setwd(cfg$checkout); source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
local({
  store <- brohn_open_store(file.path(cfg$out, "workspace"))
  checks <- list(); traces <- list(); failure <- NULL; passed <- FALSE
  real_get <- brohn_get_job; real_release <- brohn_release_eda_display_sources; real_now <- .brohn_store_now
  before_jobs <- DBI::dbGetQuery(store$con, "SELECT * FROM jobs ORDER BY rowid")
  before_versions <- DBI::dbGetQuery(store$con, "SELECT * FROM entity_versions ORDER BY rowid")
  before_objects <- DBI::dbGetQuery(store$con, "SELECT * FROM objects ORDER BY hash")
  check <- function(name, value) {
    if (!isTRUE(value)) stop(name, call. = FALSE)
    checks[[length(checks) + 1L]] <<- name; cat("PASS", name, "\n")
  }
  restore <- function() {
    assign("brohn_get_job", real_get, envir = .GlobalEnv)
    assign("brohn_release_eda_display_sources", real_release, envir = .GlobalEnv)
    assign(".brohn_store_now", real_now, envir = .GlobalEnv)
  }
  on.exit({
    restore()
    for (j in brohn_list_jobs(store, limit = 100L)) if (j$status %in% c("queued", "running")) brohn_cancel_job(store, j$id)
    brohn_write_json_file(list(schema = "brohn-eda-child-lifetime-checks/0.1", passed = passed, checks = checks,
      failure = failure, traces = traces,
      scope = "Real unchanged continuous EDA R worker, observed Python descendant and source seals. At a parent job poll, test instrumentation scans descendants with a 10ms pause between scans for at most20s while delegating actual job reads. The full scan can take longer than that pause. Bounded poll and descendant telemetry records what was observed; normal API cancellation or reclaim happens only after observing eda_display.py. No cancellation pass is inferred from an unobserved child or normal successful completion. The release wrapper checks both process identities stopped and every guard live before release, then checks every guard closed. Product polling cadence, real hosted user, wall-clock expiry, physical participant and successful preparation are not claimed."), file.path(cfg$out, "results.json"))
    brohn_close_store(store)
  }, add = TRUE)
  tryCatch({
    original <- brohn_read_json_file(file.path(cfg$out, cfg$report_file)); ref <- .brohn_rpk_ref(original)
    for (mode in c("cancel", "replace")) {
      queued <- brohn_queue_eda_display(store, ref, retry = TRUE)
      job <- brohn_claim_job(store, paste0("eda-child-original-", mode), lease_seconds = 120L)
      stopifnot(identical(job$id, queued$id))
      observation <- new.env(parent = emptyenv()); observation$injected <- FALSE; observation$release <- NULL
      observation$poll_count <- 0L; observation$scan_count <- 0L
      observation$polls <- list(); observation$descendants_seen <- list(); observation$scan_errors <- list()
      observation$telemetry_limits <- list(polls=32L,distinct_descendants=128L,scan_errors=16L,argv_items=32L,argv_item_characters=1000L)
      process_live <- function(identity) ps::ps_is_running(ps::ps_handle(identity$pid,
        time = as.POSIXct(identity$created, origin = "1970-01-01", tz = "UTC")))
      python_descendants <- function(child) {
        observation$scan_count <- observation$scan_count+1L
        scanned_at <- as.numeric(Sys.time())
        descendants <- tryCatch(ps::ps_children(ps::ps_handle(child$get_pid()), recursive = TRUE),
          error = function(e) {
            if(length(observation$scan_errors)<16L)observation$scan_errors[[length(observation$scan_errors)+1L]] <-
              list(at=scanned_at,message=substr(conditionMessage(e),1L,1000L),outer_alive=child$is_alive())
            if (!child$is_alive()) list() else stop(e)
          })
        result <- list()
        for (process in descendants) {
          # A concurrently completed process cannot be evidence of a live child.
          if (!ps::ps_is_running(process)) next
          item <- tryCatch(list(pid = ps::ps_pid(process), created = as.numeric(ps::ps_create_time(process)),
                                command = as.list(ps::ps_cmdline(process))), error = function(e) NULL)
          if(!is.null(item)) {
            key <- paste(item$pid,format(item$created,digits=17,scientific=FALSE),sep="@")
            existing <- observation$descendants_seen[[key]]
            if(!is.null(existing)) {
              existing$last_seen <- scanned_at;existing$sightings <- existing$sightings+1L
              observation$descendants_seen[[key]] <- existing
            } else if(length(observation$descendants_seen)<128L) {
              observed <- item;observed$command <- as.list(substr(head(unlist(item$command),32L),1L,1000L))
              observed$first_seen <- observed$last_seen <- scanned_at;observed$sightings <- 1L
              observation$descendants_seen[[key]] <- observed
            }
          }
          if (!is.null(item) && any(basename(gsub("\\\\", "/", unlist(item$command))) == "eda_display.py") && process_live(item))
            result[[length(result) + 1L]] <- item
        }
        result
      }
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
            entered <- as.numeric(Sys.time());observation_deadline <- entered + 20
            observation$poll_count <- observation$poll_count+1L
            scans_before <- observation$scan_count
            outer_created <- tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle(child$get_pid()))),error=function(e)NULL)
            descendants <- list()
            repeat {
              current <- real_get(current_store, id)
              if (!child$is_alive() || current$status != "running") break
              descendants <- python_descendants(child)
              if (length(descendants) || as.numeric(Sys.time()) >= observation_deadline) break
              Sys.sleep(.01)
            }
            if(length(observation$polls)<32L)observation$polls[[length(observation$polls)+1L]] <- list(
              entered_at=entered,finished_at=as.numeric(Sys.time()),outer_pid=child$get_pid(),outer_created=outer_created,
              scans=observation$scan_count-scans_before,outer_alive_after=child$is_alive(),job_status=current$status,
              matched_python=length(descendants),reason=if(length(descendants))"matched_python"else if(!child$is_alive())"outer_exited"else if(current$status!="running")"job_not_running"else"observation_deadline")
            if (!length(descendants)) return(current)
            observation$injected <- TRUE
            observation$child_pid <- child$get_pid()
            observation$child_alive_when_injected <- TRUE
            observation$python_descendants <- descendants
            observation$scratch <- get("scratch", envir = frame, inherits = FALSE)
            if (mode == "cancel") {
              brohn_cancel_job(current_store, id)
            } else {
              expiry <- current$lease_until + 1
              assign(".brohn_store_now", function() expiry, envir = .GlobalEnv)
              replacement <- tryCatch(brohn_claim_job(current_store, "eda-child-replacement", lease_seconds = 120L),
                finally = assign(".brohn_store_now", real_now, envir = .GlobalEnv))
              stopifnot(identical(replacement$id, job$id), replacement$attempt == job$attempt + 1L, !identical(replacement$token, job$token))
              observation$replacement <- replacement
            }
            current <- real_get(current_store, id)
          }
        }
        current
      }, envir = .GlobalEnv)
      assign("brohn_release_eda_display_sources", function(handle) {
        frame <- parent_frame()
        child <- if (is.null(frame)) NULL else get("child", envir = frame, inherits = FALSE)
        guards <- c(handle$guards, handle$state$extra_guards)
        live_guards <- tryCatch({.brohn_cm_guard_check(guards); TRUE}, error = function(e) FALSE)
        observed <- list(child_observed = !is.null(child), child_alive_before_release = if (is.null(child)) NULL else child$is_alive(),
          child_pid = if (is.null(child)) NULL else child$get_pid(), source_handle_open = !isTRUE(handle$state$closed),
          guarded_sources = length(handle$guards), guarded_bundle_files = length(handle$state$extra_guards),
          guards_alive_before_release = live_guards,
          python_alive_before_release = lapply(observation$python_descendants, process_live))
        real_release(handle)
        observed$source_handle_closed_after_release <- isTRUE(handle$state$closed)
        observed$guards_closed_after_release <- lapply(guards, function(guard)
          tryCatch({.brohn_cm_guard_check(list(guard)); FALSE}, error = function(e) TRUE))
        observation$release <- observed
        invisible(NULL)
      }, envir = .GlobalEnv)
      processing_error <- tryCatch({brohn_process_job(store, job, timeout_seconds = 240L);NULL},error=function(e)e, finally = restore())
      current <- real_get(store, job$id)
      observation$terminal_job <- current[c("id","operation","status","attempt","error","result")]
      traces[[mode]] <- as.list(observation)
      if(inherits(processing_error,"error"))stop(processing_error)
      check(paste(mode, "was injected only after real R and Python workers were observed alive"), isTRUE(observation$injected) && isTRUE(observation$child_alive_when_injected) && length(observation$python_descendants) > 0L)
      release <- observation$release
      check(paste(mode, "child stopped before all source guards were released"), isTRUE(release$child_observed) && identical(release$child_pid, observation$child_pid) && identical(release$child_alive_before_release, FALSE) && isTRUE(release$guards_alive_before_release) && release$guarded_sources > 0L && release$guarded_bundle_files >= 1L)
      check(paste(mode, "every observed Python descendant stopped before source release"), length(release$python_alive_before_release) == length(observation$python_descendants) && !any(unlist(release$python_alive_before_release)))
      check(paste(mode, "every native guard closed and owned scratch removed after release"), isTRUE(release$source_handle_open) && isTRUE(release$source_handle_closed_after_release) && length(release$guards_closed_after_release) == release$guarded_sources + release$guarded_bundle_files && all(unlist(release$guards_closed_after_release)) && !dir.exists(observation$scratch))
      if (mode == "cancel") {
        check("cancelled attempt stays cancelled with no publication result", current$status == "cancelled" && is.null(current$result))
      } else {
        check("obsolete child cannot overwrite the new running lease", current$status == "running" && current$attempt == observation$replacement$attempt && identical(current$token, observation$replacement$token) && is.null(current$result) && is.null(current$error))
      }
      denied <- tryCatch({brohn_publish_eda_display(store, NULL, cfg$out, job, NULL, "never-read.json"); NULL}, error = function(e) conditionMessage(e))
      check(paste(mode, "obsolete direct publication refuses at its lease fence before artifact access"), !is.null(denied) && grepl("original job lease", denied, fixed = TRUE))
      traces[[mode]]$publication_refusal <- denied
      if (current$status == "running") brohn_cancel_job(store, current$id)
      check(paste(mode, "publishes no eda display or stored object"), DBI::dbGetQuery(store$con, "SELECT COUNT(*) n FROM entities WHERE kind='eda_display'")$n[[1L]] == 0L && identical(before_objects, DBI::dbGetQuery(store$con, "SELECT * FROM objects ORDER BY hash")))
    }
    after_jobs <- DBI::dbGetQuery(store$con, "SELECT * FROM jobs ORDER BY rowid")
    check("all original scientific jobs remain exact", identical(before_jobs, after_jobs[match(before_jobs$id, after_jobs$id), , drop = FALSE]))
    check("all original source entity versions remain exact", identical(before_versions, DBI::dbGetQuery(store$con, "SELECT * FROM entity_versions ORDER BY rowid")))
    check("all original object bytes remain exact", all(vapply(before_objects$hash, function(h) identical(digest::digest(file = brohn_object_path(store, h, FALSE), algo = "sha256"), h), logical(1))))
    passed <- TRUE
  }, error = function(e) { failure <<- conditionMessage(e); stop(e) })
  cat(length(checks), "eda child lifetime checks passed\n")
})
