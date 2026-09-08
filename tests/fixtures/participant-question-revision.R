# Original material; actual launcher and read-only canonical journal inspection.
args <- commandArgs(trailingOnly = TRUE)
argument <- function(name) {i <- match(name, args); stopifnot(!is.na(i)); args[[i+1L]]}
mode <- args[[1L]]; folder <- normalizePath(argument("--folder"), winslash = "/", mustWork = TRUE)
stopifnot(grepl("^brohn-question-revision-delivery-", basename(folder)))
if (mode == "serve") {
  check_stop <- function() {if (file.exists(file.path(folder, "stop.request"))) httpuv::interrupt() else later::later(check_stop, .2)}
  later::later(check_stop, .2)
  source("scripts/run-participant.R", encoding = "UTF-8")
} else {
  source("R/platform-load.R"); brohn_load(ui = FALSE)
  store <- brohn_open_store(argument("--root"))
  local({
    on.exit(brohn_close_store(store), add = TRUE)
    if (mode == "prepare") {
      design <- brohn_new_design("Original questionnaire revision delivery", "survey")
      design$instructions <- "Original transport fixture. Answer the questions, then review this part."
      design$questions <- list(brohn_question("Original first number", "number", "end", "original-first"),
        brohn_question("Original second number", "number", "end", "original-second"),
        brohn_question("Original optional comment", "text", "end", "original-comment"),
        brohn_question("Original study information", "information", "end", "original-information"))
      design$questions[[3]]$required <- FALSE
      design$questionnaire_navigation <- brohn_questionnaire_navigation()
      brohn_put_entity(store, "study", design$id, design)
      release <- brohn_publish(store, design$id, origin = "sample", quota = 30L)
      brohn_write_json_file(list(release = release, design_hash = brohn_hash(design)), file.path(folder, "fixture.json"))
    } else if (mode == "inspect") {
      runs <- lapply(brohn_runs(store), function(run) {
        events <- brohn_run_events(store, run$id); replay <- .brohn_delivery_replay(run$protocol, events)
        list(id = run$id, protocol_hash = brohn_hash(run$protocol), design_hash = brohn_hash(run$protocol$design),
          events = events, completion = run$completion_status, transfer = run$transfer_status,
          cursor = replay$cursor, run_finished = replay$run_finished, withdrawn = replay$withdrawn,
          projection = brohn_questionnaire_run_projection(run, events, require_sealed = FALSE),
          jobs = brohn_list_jobs(store, 100L, list(run_id = run$id)))
      })
      brohn_write_json_file(list(runs = runs), file.path(folder, "inspection.json"))
    } else stop("Unknown original fixture mode.")
  })
}
