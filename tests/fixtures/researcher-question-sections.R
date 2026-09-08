# Original questions and arithmetic only; the browser authors the section graph.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source('R/platform-load.R'); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = '/', mustWork = TRUE)
stopifnot(grepl('^brohn-question-sections-ui-', basename(folder)))
workspace <- file.path(folder, 'workspace'); config_path <- file.path(folder, 'fixture.json')
if (mode == 'serve') local({
  config <- brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE = workspace, BROHN_APP_MODE = 'platform')
  services <- brohn_start_services(workspace, config$participant_port)
  on.exit(brohn_stop_services(services), add = TRUE)
  options(brohn.services = services); brohn_monitor_services(services)
  check_stop <- function() if (file.exists(file.path(folder, 'stop.request'))) shiny::stopApp() else later::later(check_stop, .2)
  later::later(check_stop, .2)
  shiny::runApp('.', host = '127.0.0.1', port = config$port, launch.browser = FALSE)
}) else local({
  store <- brohn_open_store(workspace); on.exit(brohn_close_store(store), add = TRUE)
  if (mode == 'create') {
    stopifnot(!file.exists(config_path)); brohn_initialise_library(store)
    d <- brohn_new_design('Original refill-pack questionnaire sections', 'comparison', 'study-original-sections')
    d$measures <- list('questionnaire'); d$order <- 'fixed'; d$baseline_ms <- 0L; d$fixation_ms <- 0L; d$seed <- 41717L
    d$instructions <- 'Original synthetic packaging questions for software QA. No human data or timing qualification is claimed.'
    for (i in seq_along(d$stimuli)) {
      d$stimuli[[i]]$title <- paste(c('Standard', 'Easy-grip')[[i]], 'original refill pack')
      d$stimuli[[i]]$content <- paste('Original packaging concept:', c('smooth refill cylinder', 'textured refill grip')[[i]])
      d$stimuli[[i]]$duration_ms <- 100L
    }
    driver <- brohn_question('Do you currently buy refill packs?', 'single_choice', 'before', 'q-original-driver')
    driver$options <- list(list(id = 'false', label = 'No current refills', value = FALSE), list(id = 'zero', label = 'Zero as a numeric code', value = 0), list(id = 'true', label = 'Current refill buyer', value = TRUE))
    number <- function(prompt, id, scope = 'before') {q <- brohn_question(prompt, 'number', scope, id); q$min <- 0; q$max <- 10; q$step <- 1; q}
    follow <- number('How many refill packs would you try?', 'q-original-follow')
    follow$show_if <- list(op = 'and', rules = list(list(op = 'answered', question_id = driver$id), list(op = 'equals', question_id = driver$id, value = FALSE)))
    ratings <- lapply(1:2, function(i) {
      q <- brohn_question(c('This pack seems easy to handle.', 'This pack seems awkward to handle.')[[i]], 'rating', 'before', paste0('q-original-scale-', i))
      q$min <- 0; q$max <- 4
      q$options <- lapply(0:4, function(value) list(id = paste0('rating-', i, '-', value), label = as.character(value), value = value))
      q
    })
    independent <- list(number('How often do you shop for household products?', 'q-original-frequency'),
      number('How important is compact storage?', 'q-original-storage'), number('How important is a clear label?', 'q-original-label'),
      number('How important is a reusable container?', 'q-original-reuse'))
    d$questions <- c(list(driver, follow), ratings, independent, list(number('How many future refill purchases would you consider?', 'q-original-end', 'end')))
    d$scales <- list(list(schema = 'brohn-questionnaire-scale/1.0', id = 'scale-original-handling', label = 'Original handling composite', version = 'original-1',
      source = 'Original two-item arithmetic fixture only; not an established psychological instrument.', scope = 'before',
      items = list(list(question_id = ratings[[2]]$id, reverse = TRUE, min = 0, max = 4), list(question_id = ratings[[1]]$id, reverse = FALSE, min = 0, max = 4)),
      scoring = list(aggregation = 'mean', missing = 'complete', minimum_answered = 2L, prorate = FALSE), conversion = list(min = 0, max = 100)))
    brohn_put_entity(store, 'study', d$id, d)
    brohn_write_json_file(list(workspace = workspace, port = httpuv::randomPort(min = 20000L, max = 43999L), participant_port = httpuv::randomPort(min = 44000L, max = 59000L),
      title = d$title, study_id = d$id, original = d, answers = list(list(driver = FALSE, control = list(0, 1), test = list(4, 0), expected = list(37.5, 100)),
        list(driver = 0, control = list(2, 4), test = list(0, 0), expected = list(25, 50)))), config_path)
  }
  config <- brohn_read_json_file(config_path); reports <- brohn_list_entities(store, 'report', limit = 10000L)
  snapshot <- list(study = brohn_study(store, config$study_id), studies = brohn_studies(store, archived = NULL), templates = brohn_list_entities(store, 'template'),
    releases = brohn_deployments(store), runs = lapply(brohn_runs(store), function(run) c(run, list(events = brohn_run_events(store, run$id),
      protocol_hash = brohn_run_protocol(store, run$id, run$study_id, 'default')$hash))),
    reports = reports, jobs = brohn_list_jobs(store, limit = 10000L), report_integrity = lapply(reports, function(report) {
      object <- brohn_object_path(store, report$body$result_object$hash, verify = TRUE); envelope <- brohn_read_json_file(object)
      list(id = report$id, hash_matches = identical(digest::digest(file = object, algo = 'sha256'), report$body$result_object$hash),
        envelope_matches = identical(brohn_hash(envelope$report), brohn_hash(report$body[setdiff(names(report$body), 'result_object')])))
    }))
  brohn_write_json_file(snapshot, file.path(folder, 'snapshot.json'))
})
