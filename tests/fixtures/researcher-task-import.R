# Original receiver journal; actual browser performs all export/import actions.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source('R/platform-load.R', encoding = 'UTF-8'); brohn_load(ui = TRUE)
source('tests/fixtures/original-task-journal.R', encoding = 'UTF-8')
folder <- normalizePath(args[[2L]], winslash = '/', mustWork = TRUE)
stopifnot(startsWith(basename(folder), 'brohn-native-task-import-'))
workspace <- file.path(folder, 'workspace'); config_path <- file.path(folder, 'fixture.json')
if (mode == 'serve') local({
  config <- brohn_read_json_file(config_path); Sys.setenv(BROHN_WORKSPACE = workspace, BROHN_APP_MODE = 'platform')
  services <- brohn_start_services(workspace, config$participant_port); on.exit(brohn_stop_services(services), add = TRUE)
  options(brohn.services = services); brohn_monitor_services(services)
  check_stop <- function() if (file.exists(file.path(folder, 'stop.request'))) shiny::stopApp() else later::later(check_stop, .2)
  later::later(check_stop, .2); shiny::runApp('.', host = '127.0.0.1', port = config$port, launch.browser = FALSE)
}) else local({
  store <- brohn_open_store(workspace); on.exit(brohn_close_store(store), add = TRUE)
  if (mode == 'create') {
    stopifnot(!file.exists(config_path)); brohn_initialise_library(store)
    d <- brohn_new_design('Original native choice RT export and reimport', 'blank', 'original-native-task-import')
    d$instructions <- 'Original synthetic journal for software QA. No observed participant or qualified timing.'
    task <- brohn_task_new('rt-deary-liewald-choice/1.0', id = 'original-native-choice-rt'); task$title <- 'Original choice RT with one retained response'
    d$blocks <- list(task); study <- brohn_put_entity(store, 'study', d$id, d)
    release <- brohn_publish(store, d$id, 'sample', alias_required = TRUE)
    start <- .brohn_delivery_start(store, release$token, list(consented = TRUE, participant_alias = '001', client_id = 'native-import-original-client', operation_id = 'native-import-original-start'))
    protocol <- brohn_run(store, start$run_id)$protocol
    events <- original_task_journal(protocol, function(t) if (!t$scored || t$trial_index == 1L) list(outcome = 'correct', rt = 500) else list(outcome = 'timeout'))
    .brohn_delivery_receive(store, start$run_id, start$access_token, list(events = events, operation_id = 'native-import-original-events'))
    .brohn_delivery_finish(store, start$run_id, start$access_token, list(outcome = 'completed', final_sequence = length(events), operation_id = 'native-import-original-finish'))
    queued <- brohn_list_jobs(store, request_filters = list(run_id = start$run_id)); for (job in queued) brohn_cancel_job(store, job$id)
    brohn_deployment_state(store, release$id, 'closed')
    evidence <- brohn_task_run_evidence(store, start$run_id, d$id, 'default', task$id)
    stopifnot(length(evidence$rows) == 48L, all(vapply(brohn_list_jobs(store), function(j) j$status == 'cancelled' && j$attempt == 0L, logical(1))))
    writeBin(charToRaw('{original invalid registry JSON'), file.path(folder, 'invalid-registry.json'))
    brohn_write_json_file(list(port = httpuv::randomPort(min = 20000L, max = 43999L), participant_port = httpuv::randomPort(min = 44000L, max = 59000L),
      study_id = d$id, title = d$title, task_id = task$id, task_title = task$title, run_id = start$run_id, study = study,
      original_evidence = evidence, events_hash = brohn_hash(events), original_job_id = queued[[1L]]$id), config_path)
  }
  config <- brohn_read_json_file(config_path); reports <- brohn_list_entities(store, 'report', limit = 10000L)
  brohn_write_json_file(list(study = brohn_study(store, config$study_id), run = brohn_run(store, config$run_id),
    events_hash = brohn_hash(brohn_run_events(store, config$run_id)), datasets = brohn_list_entities(store, 'dataset', limit = 10000L),
    reports = reports, jobs = brohn_list_jobs(store, limit = 10000L), objects = DBI::dbGetQuery(store$con, 'SELECT count(*) n FROM objects')$n[[1L]],
    report_integrity = lapply(reports, function(r) {p <- brohn_object_path(store, r$body$result_object$hash, verify = TRUE); envelope <- brohn_read_json_file(p)
      list(id = r$id, hash = digest::digest(file = p, algo = 'sha256'), exact = identical(brohn_hash(envelope$report), brohn_hash(r$body[setdiff(names(r$body), 'result_object')])))})),
    file.path(folder, 'snapshot.json'))
})
