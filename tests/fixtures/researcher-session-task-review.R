# Catalog/presentation QA only. No scientific child or observed participant.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source('R/platform-load.R', encoding = 'UTF-8'); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = '/', mustWork = TRUE)
stopifnot(startsWith(basename(folder), 'brohn-session-task-review-'))
workspace <- file.path(folder, 'workspace'); config_path <- file.path(folder, 'fixture.json')
if (mode == 'serve') {
  config <- brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE = workspace, BROHN_APP_MODE = 'platform')
  check_stop <- function() if (file.exists(file.path(folder, 'stop.request'))) shiny::stopApp() else later::later(check_stop, .2)
  later::later(check_stop, .2)
  shiny::runApp('.', host = '127.0.0.1', port = config$port, launch.browser = FALSE)
} else local({
  store <- brohn_open_store(workspace); on.exit(brohn_close_store(store), add = TRUE)
  if (mode == 'create') {
    stopifnot(!file.exists(config_path)); brohn_initialise_library(store)
    d <- brohn_new_design('Original session catalog and partial RT review', 'survey', 'original-session-task-study')
    d$instructions <- 'Original synthetic catalog and task arithmetic fixture. No observed people or timing qualification.'
    d$measures <- list('questionnaire'); d$questions <- list(brohn_question('Original explicit refill-pack liking', 'rating', 'end', 'original-task-liking'))
    task <- brohn_task_new('rt-deary-liewald-choice/1.0', id = 'original-partial-choice')
    task$title <- 'Original partial choice response task'; d$blocks <- list(task)
    d$camera <- list(schema = 'brohn-camera-policy/1.0', required = TRUE, audio = FALSE,
      consent_text = 'Original catalog fixture only; no camera is requested in a browser.',
      retention_text = 'No recording bytes are collected; retain this synthetic protocol for QA.',
      width = 640L, height = 480L, frame_rate = 15L, max_duration_s = 10, max_bytes = 1024^2, analysis_profile = 'none')
    study <- brohn_put_entity(store, 'study', d$id, d)
    old_release <- brohn_publish(store, d$id, 'sample', quota = 100)
    begin <- function(release, i) .brohn_delivery_start(store, release$token, list(consented = TRUE,
      participant_alias = sprintf('Catalog fixture %03d', i), client_id = paste0('original-catalog-client-', i), operation_id = paste0('original-start-', i)))
    starts <- list(begin(old_release, 1L))
    d$camera <- NULL; study <- brohn_save_study(store, d, study$revision)
    release <- brohn_publish(store, d$id, 'sample', quota = 100)
    for (i in 2:42) starts[[i]] <- begin(release, i)
    # Deliberately seeded catalog times make pagination's independent order exact.
    for (i in seq_along(starts)) DBI::dbExecute(store$con, 'UPDATE delivery_runs SET created_at=?,updated_at=? WHERE id=?',
      params = list(sprintf('2026-01-01T00:00:%02dZ', i), sprintf('2026-01-01T00:00:%02dZ', i), starts[[i]]$run_id))
    other <- brohn_create_study(store, 'Original unrelated catalog fixture', 'survey')
    other_design <- other$body; other_design$questions <- list(brohn_question('Original unrelated fixture question', 'rating', 'end', 'unrelated-rating'))
    other <- brohn_save_study(store, other_design, other$revision)
    other_release <- brohn_publish(store, other$id, 'sample')
    other_start <- .brohn_delivery_start(store, other_release$token, list(consented = TRUE, participant_alias = 'Unrelated fixture', client_id = 'other-client', operation_id = 'other-start'))
    for (item in list(old_release, release, other_release)) brohn_deployment_state(store, item$id, 'closed')

    # Complete original synthetic inner-task journal through the strict receiver.
    # It is separate from the deliberately uncompleted metadata-only sessions.
    compiled <- brohn_task_compile(task, 1L); step <- list(task = compiled)
    clock <- function(value) list(id = 'browser-monotonic', unit = 'ms', value = format(value, scientific = FALSE, trim = TRUE),
      instance_id = 'original-catalog-review-clock', time_origin_ms = '0')
    state <- list(active = list(instance = 'original-catalog-review-clock', time = 0, task = .brohn_task_delivery_new()))
    journal <- list(); responses <- list(); last <- 0
    send <- function(kind, data, time) {
      event <- list(clock = clock(time), payload = list(kind = kind, data = data))
      state <<- .brohn_task_delivery_apply(state, event, step); journal[[length(journal)+1L]] <<- event; last <<- time
    }
    for (trial in compiled$timeline) {
      t <- state$active$task
      if (trial$type == 'task_instructions') {
        send('task_instructions', list(task_id = compiled$id, step_id = trial$id, block_id = trial$block_id, clock = clock(last)), last); next
      }
      boundary <- max(brohn_default(t$boundary_time, 0), if (is.null(t$previous_response)) 0 else t$previous_response+t$previous_intertrial)
      onset <- boundary+trial$foreperiod_ms
      send('task_trial_started', list(task_id = compiled$id, trial_id = trial$id, block_id = trial$block_id, clock = clock(onset),
        observed_foreperiod_ms = trial$foreperiod_ms, scheduled_foreperiod_ms = trial$foreperiod_ms,
        observed_gap_since_previous_response_ms = if (is.null(t$previous_response)) NULL else onset-t$previous_response,
        timing_reference = 'requestAnimationFrame_before_paint', viewport = list(width = 800, height = 600, device_pixel_ratio = 1),
        stimulus_rect = list(x = 100, y = 100, width = 50, height = 50)), onset)
      answered <- !trial$scored || trial$trial_index == 1L; rt <- if (answered) 500 else NULL; code <- if (answered) trial$correct_code else NULL
      finish <- onset+if (answered) 500 else trial$timeout_ms
      response <- list(task_id = compiled$id, trial_id = trial$id, block_id = trial$block_id,
        outcome = if (answered) 'correct' else 'timeout', clock = clock(finish), response_code = code, final_code = code,
        first_correct = answered, first_response_ms = rt, final_correct_ms = rt, clock_instance_id = 'original-catalog-review-clock',
        onset_ms = onset, foreperiod_start_ms = boundary, observed_foreperiod_ms = trial$foreperiod_ms,
        anticipatory_count = 0L, keypresses = if (answered) list(list(code = code, clock = clock(finish), rt_ms = 500,
          accepted = TRUE, phase = 'response', correct = TRUE, ignored_reason = NULL)) else list(), frame_count = 1L, max_frame_gap_ms = 16)
      send('task_trial_finished', response, finish); responses[[length(responses)+1L]] <- response
    }
    .brohn_task_delivery_complete(state, step, list(clock = clock(last)))
    stopifnot(length(state$active$task$completed) == 48L)
    score <- brohn_task_score(compiled, responses); score$title <- compiled$title
    score$participant_id <- '001'; score$participant_linkage <- TRUE; score$session_id <- 'original-direct-replay'
    metric <- function(name) Filter(function(m) m$name == name, score$metrics)[[1L]]
    stopifnot(score$eligible, score$status == 'partial', metric('test_omission_rate')$value == 39/40,
      metric('test_omission_rate')$support$denominator == 40, is.null(metric('correct_test_rt_sd')$value), !metric('correct_test_rt_sd')$eligible)
    journal_object <- brohn_store_object(store, bytes = charToRaw(enc2utf8(brohn_json(list(protocol = compiled, journal = journal)))), media_type = 'application/json')
    report <- list(id = 'original-mixed-rt-review-report', study_id = d$id, title = 'Original mixed questionnaire and partial RT report',
      origin = 'sample', status = 'ready', created_at = brohn_now(),
      analysis = list(kind = 'questionnaire', task_scores = list(score), features = list(), contrasts = list(),
        observations = list(list(participant_id = '001', session_id = 'original-direct-replay', question_id = d$questions[[1L]]$id, value = 5, origin = 'sample')),
        quality = list(sessions = 1L, response_rows = 1L), parameters = list(), limitations = list('Original synthetic direct receiver/scorer fixture; no worker, observed person or timing qualification.')),
      provenance = list(design = d, origin = 'original_synthetic', journal_object = journal_object,
        execution = 'Original generated inner-task journal replayed through the strict R receiver, then scored directly. Catalog sessions are separate uncompleted fixture starts.'),
      processing = list(method = 'Direct production scorer after synthetic receiver replay; deliberately no scientific subprocess'))
    envelope <- brohn_store_object(store, bytes = charToRaw(enc2utf8(brohn_json(list(report = report)))), media_type = 'application/json')
    report$result_object <- list(hash = envelope$hash, size = envelope$size, media_type = envelope$media_type)
    brohn_put_entity(store, 'report', report$id, report)
    brohn_write_json_file(list(port = httpuv::randomPort(min = 20000L, max = 59000L), study_id = d$id, title = d$title,
      other_id = other$id, other_title = other$body$title, run_ids = lapply(starts, `[[`, 'run_id'), old_run_id = starts[[1L]]$run_id,
      old_protocol = starts[[1L]]$protocol, old_protocol_hash = brohn_run_protocol(store, starts[[1L]]$run_id, d$id, 'default')$hash,
      report_id = report$id, report = report, journal_hash = journal_object$hash), config_path)
  }
  config <- brohn_read_json_file(config_path); report <- brohn_get_entity(store, 'report', config$report_id)
  envelope <- brohn_read_json_file(brohn_object_path(store, report$body$result_object$hash, verify = TRUE))
  brohn_write_json_file(list(study = brohn_study(store, config$study_id), report = report,
    report_envelope_matches = identical(brohn_hash(envelope$report), brohn_hash(report$body[setdiff(names(report$body), 'result_object')])),
    runs = brohn_runs(store, config$study_id), jobs = brohn_list_jobs(store, limit = 10000L)), file.path(folder, 'snapshot.json'))
})
