# Inactive named-job claimant; original mutation/lease/audit body retained.
brohn_claim_variant_analysis_job <- function(store, job_id, worker, lease_seconds = 60) {
  .brohn_store_ready(store)
  brohn_require(!isTRUE(store$hosted_participant) && !RSQLite::sqliteIsTransacting(store$con),
    "Claim an explicit variant analysis in a current researcher-owned transaction.")
  job_id <- .brohn_store_text(job_id, "Job identity")
  worker <- .brohn_store_text(worker, "Worker identity")
  .brohn_store_assert(is.numeric(lease_seconds) && length(lease_seconds) == 1L &&
    is.finite(lease_seconds) && lease_seconds > 0 && lease_seconds <= 86400, "Lease duration must be in (0, 86400] seconds.")
  .brohn_store_tx(store, function() {
    if (.brohn_store_execution_paused(store)) return(NULL)
    now <- .brohn_store_now()
    rows <- DBI::dbGetQuery(store$con, paste("SELECT * FROM jobs WHERE id=? AND operation NOT IN ('acquisition_preserve','acquisition_prepare') AND (status='queued' OR",
      "(status='running' AND lease_until<=?)) ORDER BY created_at ASC,id ASC LIMIT 1"), params = list(job_id, now))
    if (!nrow(rows)) return(NULL)
    .brohn_vra_claim_admit(store, rows)
    attempt <- .brohn_store_integer(rows$attempt[[1]] + 1L, "Job attempt", 1L)
    token <- as.character(attempt)
    id <- rows$id[[1]]
    DBI::dbExecute(store$con, paste("UPDATE jobs SET status='running',attempt=?,worker=?,token=?,lease_until=?,updated_at=?",
      "WHERE id=?"), params = list(attempt, worker, token, now + lease_seconds, .brohn_store_stamp(now), id))
    .brohn_store_audit(store, "job.claimed", id, list(attempt = attempt, worker = worker, reclaimed = rows$status[[1]] == "running"))
    brohn_get_job(store, id)
  })
}
