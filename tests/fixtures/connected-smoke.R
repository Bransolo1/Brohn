# Only the serve branch writes through the real product. Inspection never seeds
# studies, responses, reports or jobs; those must come from the actual browsers.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, args[[1L]] %in% c("serve", "inspect"))
mode <- args[[1L]]; folder <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
marker <- jsonlite::fromJSON(file.path(folder, "smoke-marker.json"), simplifyVector = FALSE)
stopifnot(identical(marker$schema, "brohn-connected-smoke/1.0"),
  identical(normalizePath(Sys.getenv("BROHN_WORKSPACE"), winslash = "/", mustWork = FALSE), paste0(folder, "/workspace")))
if (mode == "serve") {
  poll <- function() {
    if (file.exists(file.path(folder, "stop.request"))) shiny::stopApp() else later::later(poll, .1)
  }
  later::later(poll, .1)
  source("scripts/run-brohn.R", encoding = "UTF-8")
  state <- getOption("brohn.services")
  stopifnot(!is.null(state), isTRUE(state$stopped), all(vapply(state$owned, function(p) !p$is_alive(), logical(1))))
  cat("connected_smoke_owned_shutdown: TRUE\n")
} else {
  stopifnot(file.exists(file.path(folder, "workspace", "catalog.sqlite")))
  source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
  local({
    store <- brohn_open_store(file.path(folder, "workspace")); on.exit(brohn_close_store(store), add = TRUE)
    studies <- Filter(function(s) identical(s$body$title, "Original portable release smoke"), brohn_list_entities(store, "study"))
    stopifnot(length(studies) <= 1L)
    study <- if (length(studies)) studies[[1L]] else NULL
    runs <- if (is.null(study)) list() else brohn_runs(store, study$id)
    reports <- Filter(function(r) !is.null(study) && identical(r$body$study_id, study$id), brohn_list_entities(store, "report"))
    bindings <- if ("delivery_run_runtimes" %in% DBI::dbListTables(store$con)) DBI::dbGetQuery(store$con,
      "SELECT run_id, deployment_id, manifest_hash FROM delivery_run_runtimes") else data.frame()
    value <- list(workspace_id = store$workspace_id, study = study,
      deployments = if (is.null(study)) list() else lapply(brohn_deployments(store, study$id), function(d) {d$token <- NULL; d}),
      runs = lapply(runs, function(r) {
        events <- brohn_run_events(store, r$id)
        list(id = r$id, status = r$completion_status, transfer_status = r$transfer_status,
          origin = r$origin, acked_sequence = r$acked_sequence,
          protocol = r$protocol, protocol_hash = brohn_hash(r$protocol), events = events, events_hash = brohn_hash(events))
      }), reports = reports, jobs = brohn_list_jobs(store),
      runtime_assignments = lapply(seq_len(nrow(bindings)), function(i) as.list(bindings[i, , drop = FALSE])))
    brohn_write_json_file(value, file.path(folder, "inspection.json"))
  })
}
