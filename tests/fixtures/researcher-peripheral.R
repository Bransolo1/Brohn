# Original source cells only. Study creation, mapping, processing and comparison
# use the actual researcher browser. This helper never seeds scientific reports.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source('R/platform-load.R'); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = '/', mustWork = TRUE)
stopifnot(grepl('^brohn-peripheral-ui-', basename(folder)))
workspace <- file.path(folder, 'workspace'); config_path <- file.path(folder, 'fixture.json')
if (mode == 'serve') local({
  config <- brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE = workspace, BROHN_APP_MODE = 'platform')
  options(shiny.maxRequestSize = 512*1024^2)
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
    ports <- c(httpuv::randomPort(min = 20000L, max = 44000L), httpuv::randomPort(min = 44001L, max = 59000L))
    brohn_write_json_file(list(port = ports[[1]], participant_port = ports[[2]], workspace = workspace,
      title = 'Original packaging temperature, handling and liking study'), config_path)
  }
  config <- brohn_read_json_file(config_path)
  studies <- brohn_list_entities(store, 'study', limit = 10000L)
  own <- Filter(function(s) identical(s$body$title, config$title), studies)
  if (mode == 'sources') {
    stopifnot(length(own) == 1L); design <- own[[1]]$body
    stopifnot(length(design$conditions) == 2L, length(design$stimuli) == 2L, length(design$questions) == 1L)
    visits <- list(list(person = '001', visit = 'V1', temperature = 2, liking = 1, acceleration = 2),
      list(person = '001', visit = 'V2', temperature = 6, liking = 3, acceleration = 3),
      list(person = '002', visit = 'V1', temperature = 8, liking = 2, acceleration = 4),
      list(person = '003', visit = 'V1', temperature = 12, liking = 4, acceleration = 5),
      list(person = '004', visit = 'V1', temperature = NA_real_, liking = 1, acceleration = NA_real_))
    temperature <- movement <- liking <- list()
    for (v in visits) for (condition in 1:2) {
      cid <- design$conditions[[condition]]$id; sid <- design$stimuli[[condition]]$id
      identity <- function(prefix) list(participant_id = paste0(prefix, '-', v$person), session_id = paste0(prefix, '-', v$visit),
        condition_id = cid, exposure_id = paste(prefix, v$person, v$visit, cid, sep = ':'))
      for (time in 0:2) temperature[[length(temperature)+1L]] <- c(identity('temp'), list(time = time,
        degrees_f = (30+if (condition == 2) v$temperature else 0)*9/5+32))
      times <- if (v$person == '001' && v$visit == 'V1' && condition == 1) c(0, 1, 10, 11) else 0:2
      for (time in times) movement[[length(movement)+1L]] <- c(identity('motion'), list(time = time,
        ax = 0, ay = 0, az = if (condition == 1) 1 else v$acceleration))
      liking[[length(liking)+1L]] <- c(identity('like'), list(stimulus_id = sid, question_id = design$questions[[1]]$id,
        value = 1+if (condition == 2) v$liking else 0))
    }
    write_source <- function(rows, filename) {
      columns <- names(rows[[1L]])
      data <- as.data.frame(stats::setNames(lapply(columns, function(column) vapply(rows, function(row) {
        value <- row[[column]]; if (is.na(value)) 'NA' else as.character(value)
      }, character(1))), columns), stringsAsFactors = FALSE, check.names = FALSE)
      file <- file.path(folder, filename)
      utils::write.table(data, file, sep = ',', row.names = FALSE, quote = TRUE, qmethod = 'double', fileEncoding = 'UTF-8')
      list(path = file, sha256 = digest::digest(file = file, algo = 'sha256'), rows = nrow(data))
    }
    bad <- temperature; bad[[2]]$time <- 0
    config$study_id <- design$id; config$study_revision <- own[[1]]$revision; config$design <- design
    config$files <- list(temperature = write_source(temperature, 'original-temperature-fahrenheit.csv'),
      bad_clock = write_source(bad, 'original-duplicated-temperature-clock.csv'),
      movement = write_source(movement, 'original-ordered-acceleration.csv'),
      liking = write_source(liking, 'original-explicit-liking.csv'))
    config$oracle <- list(temperature_estimate = 8, temperature_people = 3, temperature_visits = 4,
      liking_estimate = 2.25, liking_people = 4, liking_visits = 5,
      temperature_source_rows = 30, temperature_usable_samples = 27, temperature_supported_span = 18,
      temperature_events = 3, movement_source_rows = 31, movement_usable_samples = 28,
      movement_contrast_reason = 'duplicate_or_ambiguous_observation_identity', standard_gravity = 9.80665)
    brohn_write_json_file(config, config_path)
  }
  if (mode == 'slow-source') {
    file <- file.path(folder, 'original-slow-temperature.csv')
    data <- data.frame(participant_id = rep('slow-001', 3), session_id = rep('slow-V1', 3),
      condition_id = rep(config$design$conditions[[1]]$id, 3), exposure_id = rep('original-slow-control', 3),
      time = c('0', '10', '20'), degrees_f = c('68', '69.8', '71.6'), stringsAsFactors = FALSE)
    if (!file.exists(file)) utils::write.table(data, file, sep = ',', row.names = FALSE, quote = TRUE,
      qmethod = 'double', fileEncoding = 'UTF-8')
    config$files$slow <- list(path = file, sha256 = digest::digest(file = file, algo = 'sha256'), rows = 3)
    brohn_write_json_file(config, config_path)
  }
  datasets <- brohn_list_entities(store, 'dataset', limit = 10000L)
  reports <- brohn_list_entities(store, 'report', limit = 10000L)
  snapshot <- list(studies = studies, datasets = lapply(datasets, function(d) list(id = d$id, revision = d$revision,
    body = d$body, body_hash = brohn_hash(d$body), source_sha256 = digest::digest(file = brohn_object_path(store, d$body$source$hash), algo = 'sha256'))),
    ingestions = brohn_list_entities(store, 'ingestion', limit = 10000L), reports = reports,
    report_integrity = lapply(reports, function(record) {
      object <- record$body$result_object; path <- brohn_object_path(store, object$hash)
      envelope <- brohn_read_json_file(path)
      list(id = record$id, object_hash_matches = identical(digest::digest(file = path, algo = 'sha256'), object$hash),
        envelope_matches = identical(brohn_hash(envelope$report), brohn_hash(record$body[setdiff(names(record$body), 'result_object')])))
    }),
    jobs = lapply(brohn_list_jobs(store, limit = 10000L), function(j) j[intersect(c('id', 'operation', 'request', 'status', 'result', 'error'), names(j))]))
  brohn_write_json_file(snapshot, file.path(folder, 'snapshot.json'))
})
