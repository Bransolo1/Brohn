# Original legacy-shaped mixed-code study; no observed people or worker outputs.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source('R/platform-load.R'); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = '/', mustWork = TRUE)
stopifnot(grepl('^brohn-option-assignment-ui-', basename(folder)))
workspace <- file.path(folder, 'workspace'); config_path <- file.path(folder, 'fixture.json')
if (mode == 'serve') {
  config <- brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE = workspace, BROHN_APP_MODE = 'platform', BROHN_PARTICIPANT_PORT = config$participant_port)
  check_stop <- function() if (file.exists(file.path(folder, 'stop.request'))) shiny::stopApp() else later::later(check_stop, .2)
  later::later(check_stop, .2)
  shiny::runApp('.', host = '127.0.0.1', port = config$port, launch.browser = FALSE)
} else local({
  store <- brohn_open_store(workspace); on.exit(brohn_close_store(store), add = TRUE)
  if (mode == 'create') {
    stopifnot(!file.exists(config_path)); brohn_initialise_library(store)
    design <- brohn_new_design('Original refill-pack option assignment', 'comparison', 'study-original-option-order')
    design$instructions <- 'These are original synthetic packaging questions for software QA. No person or device is measured.'
    design$seed <- 8253L; design$order <- 'fixed'; design$baseline_ms <- 0L; design$fixation_ms <- 0L
    design$measures <- list('questionnaire')
    for (i in seq_along(design$stimuli)) {
      design$stimuli[[i]]$title <- paste(c('Standard', 'Easy-grip')[[i]], 'refill pack')
      design$stimuli[[i]]$content <- paste('Original text concept:', c('smooth cylinder', 'textured grip panel')[[i]])
      design$stimuli[[i]]$duration_ms <- 100L
    }
    values <- list(0, FALSE, '0', '1', 1, TRUE)
    labels <- c('Refillable: number zero', 'Easy opening: boolean false', 'Compact: text zero',
      'Ingredient clarity: text one', 'Recyclable: number one', 'Visible volume: boolean true')
    scopes <- c('before', 'after_each', 'end')
    prompts <- c('Which original packaging feature matters before viewing?', 'Which feature matters for this original pack?',
      'Which feature matters after comparing the original packs?')
    design$questions <- lapply(seq_along(scopes), function(i) {
      q <- brohn_question(prompts[[i]], 'single_choice', scopes[[i]], paste0('q-original-order-', i))
      q$option_assignment <- NULL
      q$randomize_options <- i != 3L
      q$options <- lapply(seq_along(values), function(j) list(id = paste0('option-original-', i, '-', j), label = labels[[j]], value = values[[j]]))
      q
    })
    brohn_put_entity(store, 'study', design$id, design)
    release <- brohn_publish(store, design$id, origin = 'sample', quota = 20L, alias_required = TRUE)
    config <- list(origin = 'original_synthetic', workspace = workspace, workspace_id = store$workspace_id,
      port = httpuv::randomPort(min = 20000L, max = 43999L), participant_port = httpuv::randomPort(min = 44000L, max = 59000L),
      study_id = design$id, title = design$title, legacy_design = design, legacy_hash = brohn_hash(design), legacy_release = release,
      legacy_protocols = lapply(1:2, function(i) brohn_compile(design, i)), values = values, labels = as.list(labels))
    brohn_write_json_file(config, config_path)
  }
  config <- brohn_read_json_file(config_path)
  if (mode == 'cancel-queued') for (job in brohn_list_jobs(store, limit = 10000L)) if (job$status == 'queued')
    brohn_cancel_job(store, job$id)
  runs <- brohn_runs(store)
  result <- list(study = brohn_study(store, config$study_id), study_hash = brohn_hash(brohn_study(store, config$study_id)$body), studies = brohn_studies(store, archived = NULL),
    templates = brohn_list_entities(store, 'template'), deployments = brohn_deployments(store),
    runs = lapply(runs, function(run) c(run, list(events = brohn_run_events(store, run$id),
      protocol_hash = brohn_run_protocol(store, run$id, run$study_id, 'default')$hash))),
    reports = brohn_list_entities(store, 'report'), jobs = brohn_list_jobs(store, limit = 10000L),
    legacy_release_design = .brohn_delivery_design(.brohn_delivery_deployment_row(store, id = config$legacy_release$id)))
  brohn_write_json_file(result, file.path(folder, 'snapshot.json'))
})
