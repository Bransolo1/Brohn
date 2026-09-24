# Original synthetic GNAT acceptance. Only the real app writes studies and data.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, args[[1L]] %in% c("serve", "inspect"))
mode <- args[[1L]]; folder <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
marker <- jsonlite::fromJSON(file.path(folder, "gnat-marker.json"), simplifyVector = FALSE)
stopifnot(identical(marker$schema, "brohn-researcher-gnat/1.0"),
  identical(normalizePath(Sys.getenv("BROHN_WORKSPACE"), winslash = "/", mustWork = FALSE), paste0(folder, "/workspace")))
if (mode == "serve") {
  poll <- function() {
    if (file.exists(file.path(folder, "stop.request"))) shiny::stopApp() else later::later(poll, .1)
  }
  later::later(poll, .1)
  source("scripts/run-brohn.R", encoding = "UTF-8")
  state <- getOption("brohn.services")
  stopifnot(!is.null(state), isTRUE(state$stopped), all(vapply(state$owned, function(p) !p$is_alive(), logical(1))))
  cat("researcher_gnat_owned_shutdown: TRUE\n")
} else {
  stopifnot(file.exists(file.path(folder, "workspace", "catalog.sqlite")))
  source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
  local({
    store <- brohn_open_store(file.path(folder, "workspace")); on.exit(brohn_close_store(store), add = TRUE)
    studies <- brohn_list_entities(store, "study", limit = 100L)
    reports <- brohn_list_entities(store, "report", limit = 100L)
    bindings <- if ("delivery_run_runtimes" %in% DBI::dbListTables(store$con))
      brohn_rows(DBI::dbGetQuery(store$con, "SELECT run_id,deployment_id,manifest_hash FROM delivery_run_runtimes")) else list()
    value <- list(workspace_id = store$workspace_id, studies = studies,
      releases = unlist(lapply(studies, function(s) lapply(brohn_deployments(store, s$id), function(d) {
        d$token <- NULL; d
      })), recursive = FALSE),
      sessions = lapply(brohn_runs(store), function(r) list(run = r, events = brohn_run_events(store, r$id),
        receipts = brohn_rows(DBI::dbGetQuery(store$con,
          "SELECT operation,operation_id,request_hash FROM delivery_receipts WHERE scope=? ORDER BY operation,operation_id", params = list(r$id))))),
      reports = reports, jobs = brohn_list_jobs(store, limit = 100L),
      datasets = brohn_list_entities(store, "dataset", limit = 100L),
      templates = brohn_list_entities(store, "template", limit = 100L), runtime_assignments = bindings,
      report_integrity = lapply(reports, function(r) {
        p <- brohn_object_path(store, r$body$result_object$hash, verify = TRUE); envelope <- brohn_read_json_file(p)
        list(id = r$id, sha256 = digest::digest(file = p, algo = "sha256"),
          exact = identical(brohn_hash(envelope$report), brohn_hash(r$body[setdiff(names(r$body), "result_object")])))
      }))
    brohn_write_json_file(value, file.path(folder, "snapshot.json"))
  })
}
