# Actual supervised R processes, immutable report publication and cancellation.
source("R/platform-load.R", encoding="UTF-8"); brohn_load(ui=FALSE)
source("tests/fixtures/platform-analysis-fixture.R")
local({
  checks <- 0L
  check <- function(name,ok) {if (!isTRUE(ok)) stop(paste("Job QA failed:",name),call.=FALSE); checks <<- checks+1L}
  near <- function(a,b) is.numeric(a) && length(a)==1 && abs(a-b)<1e-9
  rejected <- function(expr) inherits(try(force(expr),silent=TRUE),"try-error")
  root <- tempfile("brohn-job-qa-"); dir.create(root); root <- normalizePath(root,winslash="/")
  store <- brohn_open_store(file.path(root,"workspace")); controller <- NULL
  on.exit({
    if (!is.null(controller) && controller$is_alive()) controller$kill_tree()
    brohn_close_store(store)
    actual <- normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),grepl("^brohn-job-qa-",basename(actual)))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  brohn_initialise_library(store)
  f <- researcher_analysis_fixture()
  study <- brohn_put_entity(store,"study",f$design$id,f$design)
  source_path <- file.path(root,"original-gaze.csv")
  utils::write.csv(f$gaze,source_path,row.names=FALSE,na="",fileEncoding="UTF-8")
  ingested <- brohn_ingest_dataset(store,source_path,"Original researcher fixture",modality="gaze",study_id=f$design$id,origin="sample")
  check("ingested dataset requires explicit mapping",ingested$body$status=="needs_mapping")
  check("unaccepted dataset cannot be queued",rejected(brohn_queue_dataset(store,ingested$id)))
  accepted <- brohn_curate_dataset(store,ingested$id,f$gaze_mapping,ingested$revision)
  check("acceptance retains immutable source and new dataset revision",accepted$revision==2 && identical(accepted$body$source$hash,ingested$body$source$hash))
  queued <- brohn_queue_dataset(store,accepted$id)
  again <- brohn_queue_dataset(store,accepted$id)
  check("identical queued analysis is idempotent",identical(queued$id,again$id))
  claimed <- brohn_claim_job(store,"researcher-qa",lease_seconds=60)
  check("actual claim supplies attempt fence",claimed$status=="running" && claimed$attempt==1)
  # A later draft amendment must not alter the already queued analysis.
  revised <- f$design; revised$title <- "Amended geometry"; revised$stimuli[[1]]$aois[[1]]$width <- 0.2
  invisible(brohn_save_study(store,revised,study$revision))
  brohn_process_job(store,claimed,timeout_seconds=30)
  finished <- brohn_get_job(store,claimed$id)
  if (finished$status!="succeeded") stop(paste("Real worker failed:",brohn_json(finished$error)),call.=FALSE)
  check("real R child produces succeeded job",finished$status=="succeeded")
  report <- brohn_get_entity(store,"report",finished$result$report_id)
  check("real report reproduces independent 10.833333 pp gaze mean",near(report$body$analysis$contrasts[[1]]$estimate,10.833333333333334))
  check("queued study revision remains frozen despite edit",report$body$provenance$study_revision==1 && report$body$provenance$design$title==f$design$title && report$body$provenance$design$stimuli[[1]]$aois[[1]]$width==0.5)
  check("report origin and draft method retained",report$body$origin=="sample" && report$body$analysis$parameters$method=="aoi-valid-gaze-time-share/0.1.0-draft")
  check("result object SHA agrees with publication receipt",identical(report$body$result_object$hash,finished$result$output_hash) && identical(digest::digest(file=brohn_object_path(store,report$body$result_object$hash),algo="sha256"),finished$result$output_hash))
  identities <- report$body$processing$code_hashes
  check("report records actual worker input and loaded code identities", nchar(report$body$processing$request_hash)==64 &&
    all(c("R/platform-core.R", "R/platform-analysis.R", "R/platform-gaze.R", "scripts/analysis-worker.R") %in% names(identities)) &&
    all(vapply(names(identities), function(path) identical(identities[[path]], digest::digest(file=path,algo="sha256")), logical(1))))
  report_hash <- brohn_hash(report$body)
  second_job <- brohn_queue_dataset(store,accepted$id,revision=2)
  check("changed AOI study revision creates distinct analysis",!identical(second_job$id,finished$id))
  second_claim <- brohn_claim_job(store,"researcher-qa",lease_seconds=60)
  brohn_process_job(store,second_claim,timeout_seconds=30)
  second_finished <- brohn_get_job(store,second_job$id)
  check("reanalysis also finishes via actual R child",second_finished$status=="succeeded")
  second_report <- brohn_get_entity(store,"report",second_finished$result$report_id)
  check("changed control AOI gives independently expected 45 pp",near(second_report$body$analysis$contrasts[[1]]$estimate,45))
  check("prior result remains immutable and independently reopenable",identical(report_hash,brohn_hash(brohn_get_entity(store,"report",report$id)$body)) && length(brohn_entity_history(store,"report",report$id))==1)
  check("reanalysis source bytes remain unchanged",identical(digest::digest(file=brohn_object_path(store,accepted$body$source$hash),algo="sha256"),accepted$body$source$hash))

  # Corrupt request identity: no report may be published for the wrong dataset.
  corrupt_request <- second_job$request; corrupt_request$dataset_hash <- paste(rep("0",64),collapse="")
  corrupt_job <- brohn_enqueue_job(store,"analyse_dataset",corrupt_request,"qa-corrupt-request")
  corrupt_claim <- brohn_claim_job(store,"researcher-qa",lease_seconds=60)
  reports_before <- length(brohn_list_entities(store,"report"))
  brohn_process_job(store,corrupt_claim,timeout_seconds=30)
  check("mismatched pinned dataset fails rather than produces report",brohn_get_job(store,corrupt_job$id)$status=="failed" && length(brohn_list_entities(store,"report"))==reports_before)

  # Cancellation is sent while an independent R supervisor is preparing/running
  # the real child. Its fenced publication must not survive that cancellation.
  cancelled <- brohn_queue_dataset(store,accepted$id,revision=2,force=TRUE)
  cancel_claim <- brohn_claim_job(store,"cancel-qa",lease_seconds=60)
  controller <- processx::process$new(brohn_rscript(),c("--vanilla","tests/fixtures/platform-job-controller.R",store$root,cancel_claim$id),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  started <- Sys.time(); prepared <- FALSE
  while (controller$is_alive() && as.numeric(difftime(Sys.time(),started,units="secs"))<10) {
    requests <- list.files(file.path(store$root,"scratch"),pattern="^request\\.json$",recursive=TRUE,full.names=TRUE)
    if (any(grepl(cancel_claim$id,requests,fixed=TRUE))) {prepared <- TRUE; break}
    controller$wait(10)
  }
  check("independent supervisor reached real job preparation",prepared)
  invisible(brohn_cancel_job(store,cancel_claim$id))
  controller$wait(10000)
  check("cancelled child and supervisor terminate",!controller$is_alive())
  check("cancelled attempt cannot publish a result",brohn_get_job(store,cancelled$id)$status=="cancelled" && is.null(brohn_get_job(store,cancelled$id)$result) && length(brohn_list_entities(store,"report"))==reports_before)

  # Exercise real delivery finalization and the automatic run-analysis job. The
  # browser's separate integration test supplies transport/interaction evidence.
  run_design <- brohn_new_design("Synthetic automatic receipt analysis","survey",id="auto-run")
  run_design$instructions <- ""
  run_design$questions <- list(brohn_question("Overall liking","rating","before","q-auto"))
  invisible(brohn_put_entity(store,"study",run_design$id,run_design))
  deployment <- brohn_publish(store,run_design$id,origin="pilot",quota=2)
  session <- .brohn_delivery_start(store,deployment$token,list(consented=TRUE,client_id="synthetic-auto",operation_id="synthetic-auto-start",participant_alias=""))
  step <- session$protocol$timeline[[1]]
  event <- function(seq,type,time,payload,linked=TRUE) list(sequence=seq,id=paste0("auto-event-",seq),type=type,
    step_id=if(linked) step$id else NULL,stimulus_id=NULL,condition_id=NULL,
    question_id=if(linked) step$question$id else NULL,phase=if(linked) step$phase else "session",
    clock=list(id="browser-monotonic",unit="ms",value=as.character(time),instance_id="synthetic-auto-clock",time_origin_ms="1000"),payload=payload)
  events <- list(event(1,"step_started",10,list(resumed=FALSE)),event(2,"response",20,list(value=4,response_time_ms=10)),
    event(3,"step_finished",20,list(elapsed_ms=10)),event(4,"run_finished",30,list(outcome="completed"),FALSE))
  invisible(.brohn_delivery_receive(store,session$run_id,session$access_token,list(operation_id="synthetic-auto-events",events=events)))
  invisible(.brohn_delivery_finish(store,session$run_id,session$access_token,list(operation_id="synthetic-auto-finish",outcome="completed",final_sequence=4)))
  saved_run <- brohn_run(store,session$run_id)
  check("delivery completion retains actual saved transfer state",saved_run$completion_status=="completed" && saved_run$transfer_status=="saved")
  check("automatic display alias does not imply supplied identity",!isTRUE(saved_run$participant_alias_supplied) && nzchar(saved_run$participant_alias))
  auto_claim <- brohn_claim_job(store,"auto-run-qa",lease_seconds=60)
  check("final receipt automatically queued the correct run job",auto_claim$operation=="analyse_run" && auto_claim$request$run_id==session$run_id)
  brohn_process_job(store,auto_claim,timeout_seconds=30)
  auto_finished <- brohn_get_job(store,auto_claim$id)
  if(auto_finished$status!="succeeded") stop(paste("Automatic run worker failed:",brohn_json(auto_finished$error)),call.=FALSE)
  auto_report <- brohn_get_entity(store,"report",auto_finished$result$report_id)
  check("real automatic report preserves rating value",auto_report$body$analysis$features[[1]]$numeric_response_mean==4)
  check("automatic report suppresses unsupported unique-person inference",is.null(auto_report$body$analysis$quality$participant_count) && length(auto_report$body$analysis$contrasts)==0)
  check("automatic report pins the exact completed run",auto_report$body$provenance$runs[[1]]$run_id==session$run_id && auto_report$body$provenance$runs[[1]]$final_sequence==4)
  check("catalog integrity survives child, reanalysis and cancellation",identical(DBI::dbGetQuery(store$con,"PRAGMA integrity_check")[[1]],"ok") && nrow(DBI::dbGetQuery(store$con,"PRAGMA foreign_key_check"))==0)
  retry <- brohn_retry_processing(store, cancelled$id)
  check("retry is a new job with exactly the original frozen inputs", !identical(retry$id, cancelled$id) &&
    identical(retry$request, brohn_get_job(store, cancelled$id)$request) && retry$status == "queued")
  check("retry keeps its cancelled predecessor and audit lineage", brohn_get_job(store, cancelled$id)$status == "cancelled" &&
    any(vapply(brohn_list_entities(store, "job_retry"), function(r) identical(r$body$new_job_id, retry$id) && identical(r$body$source_job_id, cancelled$id), logical(1))))
  check("successful result cannot be silently retried", rejected(brohn_retry_processing(store, auto_finished$id)))
  cat(sprintf("PASS: %d actual job/publication assertions (R subprocess, frozen reanalysis, cancellation, automatic completed-run report)\n",checks))
})
