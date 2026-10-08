# Inactive ordinary-worker routing; no source/request migration or public loader.
.brohn_worker_analysis_profile <- "saved-variant-run-analysis/0.1"
.brohn_worker_route <- function(operation, request) {
  if (!operation %in% c("analyse_run", "analyse_cohort")) return("legacy")
  if (!"analysis_profile" %in% names(request)) return("legacy")
  if (identical(request[["analysis_profile", exact = TRUE]], .brohn_worker_analysis_profile)) return("variant")
  "unsupported"
}
brohn_worker_dispatch_ready <- function() {
  brohn_require(identical(.brohn_vra_profile, .brohn_worker_analysis_profile) &&
    is.function(brohn_process_variant_job) && is.function(.brohn_vra_claim_admit) &&
    is.function(brohn_process_job) && is.function(brohn_fail_job),
    "Install the complete registered worker implementation before claiming jobs.")
  invisible(TRUE)
}
.brohn_worker_admit_claim <- function(store, rows, caller_transaction) {
  if (!rows$operation[[1L]] %in% c("analyse_run", "analyse_cohort")) return(invisible(NULL))
  request <- .brohn_store_decode(rows$request_json[[1L]], rows$request_hash[[1L]])
  route <- .brohn_worker_route(rows$operation[[1L]], request)
  if (identical(route, "variant")) {
    brohn_require(!isTRUE(store$hosted_participant) && !caller_transaction,
      "Claim an explicit variant analysis in a current researcher-owned transaction.")
    .brohn_vra_claim_admit(store, rows)
  }
  # Unsupported profiles intentionally acquire an ordinary lease. The dispatcher
  # records a visible failed outcome, so they cannot starve later queued jobs.
  invisible(NULL)
}

brohn_claim_worker_job <- function(store, worker, lease_seconds = 60) {
  caller_transaction <- RSQLite::sqliteIsTransacting(store$con)
  worker <- .brohn_store_text(worker, "Worker identity")
  .brohn_store_assert(is.numeric(lease_seconds) && length(lease_seconds) == 1L &&
    is.finite(lease_seconds) && lease_seconds > 0 && lease_seconds <= 86400, "Lease duration must be in (0, 86400] seconds.")
  .brohn_store_tx(store, function() {
    if (.brohn_store_execution_paused(store)) return(NULL)
    now <- .brohn_store_now()
    rows <- DBI::dbGetQuery(store$con, paste("SELECT * FROM jobs WHERE operation NOT IN ('acquisition_preserve','acquisition_prepare') AND (status='queued' OR",
      "(status='running' AND lease_until<=?)) ORDER BY created_at ASC,id ASC LIMIT 1"), params = list(now))
    if (!nrow(rows)) return(NULL)
    .brohn_worker_admit_claim(store, rows, caller_transaction)
    attempt <- .brohn_store_integer(rows$attempt[[1]] + 1L, "Job attempt", 1L)
    token <- as.character(attempt)
    id <- rows$id[[1]]
    DBI::dbExecute(store$con, paste("UPDATE jobs SET status='running',attempt=?,worker=?,token=?,lease_until=?,updated_at=?",
      "WHERE id=?"), params = list(attempt, worker, token, now + lease_seconds, .brohn_store_stamp(now), id))
    .brohn_store_audit(store, "job.claimed", id, list(attempt = attempt, worker = worker, reclaimed = rows$status[[1]] == "running"))
    brohn_get_job(store, id)
  })
}
brohn_process_worker_job <- function(store, job, timeout_seconds = 1900) {
  route <- .brohn_worker_route(job$operation, job$request)
  if (identical(route, "variant")) return(brohn_process_variant_job(store, job, timeout_seconds))
  if (identical(route, "unsupported")) {
    brohn_fail_job(store, job$id, job$worker, job$token,
      list(message = "This worker does not support the saved analysis profile. The original request is preserved.",
        code = "unsupported_analysis_profile"))
    return(invisible(NULL))
  }
  brohn_process_job(store, job, timeout_seconds)
}
