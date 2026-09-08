# Original synthetic sources; actual browser reviews and queues the cohorts.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source('R/platform-load.R', encoding = 'UTF-8'); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = '/', mustWork = TRUE)
stopifnot(startsWith(basename(folder), 'brohn-researcher-task-cohort-'))
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
    f <- brohn_read_json_file('tests/fixtures/task-import/manifest.json')$fixtures$choice
    registry_path <- file.path('tests/fixtures/task-import', f$registry); registry <- brohn_read_json_file(registry_path)
    original <- brohn_read_table(file.path('tests/fixtures/task-import', f$csv), 'csv', 20000L)
    d <- brohn_new_design('Original task cohort browser study', 'blank', brohn_id('study')); d$blocks <- list(registry$task)
    d$instructions <- 'Original synthetic software qualification sources. No observed participant or physical timing claim.'
    study <- brohn_put_entity(store, 'study', d$id, d)
    rows <- function(person, session, value, wrong = FALSE, partial = FALSE) {
      x <- original; x[[f$metadata$participant_column]] <- person; x[[f$metadata$session_column]] <- session
      x[[f$metadata$attempt_column]] <- 'original-attempt'; x[[f$metadata$participant_linkage_column]] <- 'false'
      x$first_response_ms <- x$final_correct_ms <- as.character(value)
      if (wrong) {
        trials <- Filter(function(t) t$type == 'task_trial', registry$protocols[[1L]]$compiled$timeline)
        x$outcome[[9L]] <- 'incorrect'; x$first_correct[[9L]] <- 'false'
        x$first_code[[9L]] <- setdiff(unlist(trials[[9L]]$allowed_codes), trials[[9L]]$correct_code)[[1L]]
        x$final_code[[9L]] <- x$final_correct_ms[[9L]] <- ''
      }
      omitted <- if (partial) 10:48 else if (wrong) 12:48 else integer()
      if (length(omitted)) {
        x$outcome[omitted] <- 'timeout'; x$first_correct[omitted] <- 'false'
        for (field in c('first_code','final_code','first_response_ms','final_correct_ms')) x[[field]][omitted] <- ''
      }
      x
    }
    import <- function(rows, name) {
      file <- file.path(folder, paste0(name, '.csv'))
      utils::write.table(rows, file, sep = ',', quote = TRUE, row.names = FALSE, qmethod = 'double', fileEncoding = 'UTF-8', eol = '\n')
      dataset <- brohn_ingest_dataset(store, file, name, modality = 'implicit', origin = 'sample')
      ref <- brohn_stage_task_registry(store, registry_path, basename(registry_path), dataset$id, dataset$revision, study$id, study$revision, registry$task$id)
      m <- f$metadata; m$source_collection_id <- 'original-browser-register'; m$protocol_registry <- ref
      m$origin_statement <- 'Original synthetic CSV with deliberately unlinked source codes; browser QA supplies its explicit original fixture register.'
      curated <- brohn_curate_dataset(store, dataset$id, m, dataset$revision, study$id, study$revision)
      queued <- brohn_queue_dataset(store, curated$id); claim <- brohn_claim_job(store, 'original-browser-source-qa', 90L)
      stopifnot(claim$id == queued$id); brohn_process_job(store, claim, timeout_seconds = 120)
      done <- brohn_get_job(store, queued$id); if (done$status != 'succeeded') stop(brohn_json(done$error))
      brohn_get_entity(store, 'report', done$result$report_id)
    }
    first <- import(rbind(rows('P','S1',1), rows('P','S2',1), rows('Q','S1',3,wrong=TRUE)), 'Original repeat and third-error source')
    second <- import(rows('R','S1',500,partial=TRUE), 'Original one-correct and39-timeout source')
    stopifnot(all(!vapply(first$body$analysis$task_attempts, `[[`, logical(1), 'participant_linkage')))
    brohn_write_json_file(list(schema='brohn-task-cohort-browser-fixture/1.0',port=httpuv::randomPort(min=20000L,max=43999L),
      participant_port=httpuv::randomPort(min=44000L,max=59000L),study_id=d$id,title=d$title,reports=list(first,second),
      register='Original synthetic register: P has visits S1/S2; Q and R each have S1. All original CSV flags remain false. No observed human evidence.',
      expected=list(primary_mean=2,primary_error_mean=1/6,partial_mean=251.5,partial_sd_people=1)),config_path)
  }
  config <- brohn_read_json_file(config_path); reports <- brohn_list_entities(store,'report',limit=10000L)
  brohn_write_json_file(list(study=brohn_study(store,config$study_id),reports=reports,jobs=brohn_list_jobs(store,limit=10000L),
    report_integrity=lapply(reports,function(r) {
      path <- brohn_object_path(store,r$body$result_object$hash,verify=TRUE); e <- brohn_read_json_file(path)
      list(id=r$id,hash=digest::digest(file=path,algo='sha256'),exact=identical(brohn_hash(e$report),brohn_hash(r$body[setdiff(names(r$body),'result_object')])))})),
    file.path(folder,'snapshot.json'))
})
