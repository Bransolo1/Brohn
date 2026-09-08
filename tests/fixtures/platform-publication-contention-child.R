# Original process fixture; no production function is mocked or slowed.
for (module in c("platform-core", "platform-store", "platform-delivery", "platform-vision"))
  source(paste0("R/", module, ".R"), encoding = "UTF-8")
args <- commandArgs(TRUE)
mode <- args[[1L]]; request <- readRDS(args[[2L]])
store <- brohn_open_store(request$workspace)
wait_for <- function(path, seconds = 30) {
  until <- as.numeric(Sys.time()) + seconds
  while (!file.exists(path)) {
    if (as.numeric(Sys.time()) > until) stop("Test-owned process barrier timed out.")
    Sys.sleep(.002)
  }
}
stamp <- function() as.numeric(Sys.time())
if (mode == "observer") {
  app <- brohn_delivery_app(store, static_root = "www/participant")
  writeLines("ready", request$observer_ready)
  wait_for(request$entered)
  bytes <- charToRaw(.brohn_store_json(request$event_request))
  env <- list(PATH_INFO = paste0("/api/events/", request$run_id), REQUEST_METHOD = "POST",
    HTTP_HOST = "127.0.0.1:3840", HTTP_ORIGIN = "http://127.0.0.1:3840",
    HTTP_AUTHORIZATION = paste("Bearer", request$access_token), CONTENT_TYPE = "application/json",
    CONTENT_LENGTH = as.character(length(bytes)), rook.input = list(read = function(n = -1L) bytes))
  began <- stamp(); response <- app$call(env); ended <- stamp()
  saveRDS(list(started = began, ended = ended, elapsed_seconds = ended - began,
    http_status = response$status, retry_after = response$headers[["Retry-After"]],
    response = jsonlite::fromJSON(response$body, simplifyVector = FALSE)), request$observer_result)
} else if (mode == "publisher") {
  job <- brohn_get_job(store, request$job_id)
  writeLines("ready", request$publisher_ready)
  wait_for(request$go)
  entered <- NULL; began <- stamp()
  outcome <- tryCatch({
    # This is the unmodified general report publication sequence. The marker
    # only signals that BEGIN IMMEDIATE has returned; it adds no deliberate wait.
    brohn_store_batch(store, function() {
      entered <<- stamp(); writeLines(format(entered, digits = 17), request$entered)
      brohn_renew_job(store, job$id, job$worker, job$token, 60)
      analysis <- brohn_promote_worker_artifacts(store, request$analysis, request$scratch, job)
      publication <- file.path(request$scratch, "published-result.json")
      report <- list(schema_version = "brohn-report/1.0.0", id = request$report_id,
        title = "Original storage contention fixture; no scientific inference", origin = "sample", analysis = analysis)
      writeLines(brohn_json(list(schema = "brohn-analysis-output/1.0", report = report)), publication, useBytes = TRUE)
      object <- brohn_store_object(store, path = publication, media_type = "application/json")
      report$result_object <- object
      brohn_put_entity(store, "report", request$report_id, report)
      brohn_complete_job(store, job$id, job$worker, job$token, list(report_id = request$report_id, output_hash = object$hash))
    })
    list(status = "succeeded")
  }, error = function(e) list(status = "error", message = conditionMessage(e)))
  ended <- stamp()
  saveRDS(c(list(started = began, lock_entered = entered, ended = ended,
    elapsed_seconds = ended - began, lock_seconds = ended - entered), outcome), request$publisher_result)
} else stop("Unknown isolated fixture mode.")
brohn_close_store(store)
