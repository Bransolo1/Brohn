# Original consumer-research questions. The browser enables answer review.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source('R/platform-load.R', encoding = 'UTF-8'); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = '/', mustWork = TRUE)
stopifnot(startsWith(basename(folder), 'brohn-question-revision-ui-'))
workspace <- file.path(folder, 'workspace'); config_path <- file.path(folder, 'fixture.json')
if (mode == 'serve') local({
  config <- brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE = workspace, BROHN_APP_MODE = 'platform')
  services <- brohn_start_services(workspace, config$participant_port)
  on.exit(brohn_stop_services(services), add = TRUE)
  options(brohn.services = services); brohn_monitor_services(services)
  stop_owned <- function() if (file.exists(file.path(folder, 'stop.request'))) shiny::stopApp() else later::later(stop_owned, .2)
  later::later(stop_owned, .2)
  shiny::runApp('.', host = '127.0.0.1', port = config$port, launch.browser = FALSE)
}) else local({
  store <- brohn_open_store(workspace); on.exit(brohn_close_store(store), add = TRUE)
  if (mode == 'create') {
    stopifnot(!file.exists(config_path)); brohn_initialise_library(store)
    d <- brohn_new_design('Original refill-pack answer review', 'comparison', 'study-original-answer-review')
    d$measures <- list('questionnaire'); d$order <- 'fixed'; d$baseline_ms <- 0L; d$fixation_ms <- 0L; d$seed <- 22783L
    d$instructions <- 'Original synthetic software walkthrough. Review each questionnaire before continuing. These short stimuli check delivery, not research timing.'
    for (i in seq_along(d$stimuli)) {
      d$stimuli[[i]]$title <- paste(c('Standard', 'Easy-grip')[[i]], 'original refill pack')
      d$stimuli[[i]]$content <- paste('Original concept:', c('smooth refill cylinder', 'textured refill grip')[[i]])
      d$stimuli[[i]]$duration_ms <- 100L
    }
    number <- function(prompt, id, scope = 'before') {q <- brohn_question(prompt, 'number', scope, id); q$min <- 0; q$max <- 10; q$step <- 1; q}
    driver <- brohn_question('Which refill experience applies to you?', 'single_choice', 'before', 'q-review-driver')
    driver$options <- list(list(id = 'original-false', label = 'No current refill purchases', value = FALSE),
      list(id = 'original-zero', label = 'Zero purchases as a numeric code', value = 0))
    direct <- number('How many refill packs would you try?', 'q-review-dependent')
    direct$show_if <- list(op = 'equals', question_id = driver$id, value = FALSE)
    transitive <- number('How many of those packs would you share?', 'q-review-transitive')
    transitive$show_if <- list(op = 'answered', question_id = direct$id)
    remains <- number('How certain are you about that refill experience?', 'q-review-still-visible')
    remains$show_if <- list(op = 'answered', question_id = driver$id)
    independent <- number('How often do you shop for household products?', 'q-review-independent')
    optional <- brohn_question('Any optional comments before viewing the packs?', 'text', 'before', 'q-review-optional')
    optional$required <- FALSE
    information <- brohn_question('Next you will see two original refill-pack concepts.', 'information', 'before', 'q-review-information')
    after <- number('How easy would this pack be to handle?', 'q-review-after', 'after_each')
    scale_questions <- lapply(1:2, function(i) brohn_question(c('Overall, these packs seem practical.', 'Overall, these packs seem convenient.')[[i]],
      'rating', 'end', paste0('q-review-scale-', i)))
    end_zero <- number('How many current purchases did the numeric code describe?', 'q-review-end-zero', 'end')
    end_zero$show_if <- list(op = 'equals', question_id = driver$id, value = 0)
    d$questions <- c(list(driver, direct, transitive, remains, independent, optional, information, after), scale_questions, list(end_zero))
    d$scales <- list(list(schema = 'brohn-questionnaire-scale/1.0', id = 'scale-original-review-mean',
      label = 'Original practical-convenient mean', version = 'original-1',
      source = 'Original two-item arithmetic fixture; not an established psychological instrument.', scope = 'end',
      items = lapply(scale_questions, function(q) list(question_id = q$id, reverse = FALSE, min = 1, max = 7)),
      scoring = list(aggregation = 'mean', missing = 'complete', minimum_answered = 2L, prorate = FALSE), conversion = NULL))
    brohn_put_entity(store, 'study', d$id, d)
    legacy <- brohn_publish(store, d$id, 'sample', alias_required = TRUE)
    brohn_write_json_file(list(workspace = workspace, port = httpuv::randomPort(min = 20000L, max = 43999L),
      participant_port = httpuv::randomPort(min = 44000L, max = 59000L), title = d$title, study_id = d$id,
      original = d, legacy_release = legacy, expected_scale = 5), config_path)
  }
  config <- brohn_read_json_file(config_path); reports <- brohn_list_entities(store, 'report', limit = 10000L)
  snapshot <- list(study = brohn_study(store, config$study_id), studies = brohn_studies(store, archived = NULL),
    templates = brohn_list_entities(store, 'template'), releases = brohn_deployments(store),
    runs = lapply(brohn_runs(store), function(run) {
      events <- brohn_run_events(store, run$id)
      projection <- if (!is.null(run$protocol$design$questionnaire_navigation)) brohn_questionnaire_run_projection(run, events, FALSE) else NULL
      c(run, list(events = events, projection = projection, protocol_hash = brohn_run_protocol(store, run$id, run$study_id, 'default')$hash))
    }), reports = reports, jobs = brohn_list_jobs(store, limit = 10000L), report_integrity = lapply(reports, function(report) {
      path <- brohn_object_path(store, report$body$result_object$hash, verify = TRUE); envelope <- brohn_read_json_file(path)
      list(id = report$id, hash_matches = identical(digest::digest(file = path, algo = 'sha256'), report$body$result_object$hash),
        exact = identical(brohn_hash(envelope$report), brohn_hash(report$body[setdiff(names(report$body), 'result_object')])) )
    }))
  brohn_write_json_file(snapshot, file.path(folder, 'snapshot.json'))
})
