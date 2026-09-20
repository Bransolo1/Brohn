source("R/platform-load.R"); brohn_load(ui = FALSE)
source("R/platform-capture.R")
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Camera QA failed: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-camera-qa-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace")); brohn_initialise_library(store)
  on.exit({brohn_close_store(store); actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-camera-qa-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)}, add = TRUE)
  policy <- list(schema = "brohn-camera-policy/1.0", required = TRUE, audio = FALSE,
    consent_text = "Original synthetic camera recording test consent.", retention_text = "Original generated fixtures retained only for testing.",
    width = 640, height = 480, frame_rate = 15, max_duration_s = 10, max_bytes = 8*1024^2, analysis_profile = "none")
  brohn_validate_camera_policy(policy)
  check("explicit bounded camera policy validates", TRUE)
  bad <- policy; bad$audio <- "false"; check("audio consent does not coerce string false", rejects(brohn_validate_camera_policy(bad)))
  bad <- policy; bad$max_bytes <- 128*1024^2+1; check("oversized policy rejects", rejects(brohn_validate_camera_policy(bad)))
  fixture <- file.path(root, "original.webm")
  ffmpeg <- processx::run(Sys.which("ffmpeg"), c("-nostdin", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x480:rate=15", "-t", "2", "-an", "-c:v", "libvpx", "-deadline", "realtime", "-cpu-used", "8", "-y", fixture),
    timeout = 30000, windows_hide_window = TRUE)
  video <- readBin(fixture, "raw", n = file.info(fixture)$size)
  check("original generated WebM has one bounded container", .brohn_camera_webm_container(fixture)$status == "single_webm_container")
  combined <- file.path(root, "separate-recorders.webm"); writeBin(c(video, video), combined)
  check("separately initialized containers are not concatenated", rejects(.brohn_camera_webm_container(combined)))
  counter <- 0L
  uuid <- function() {counter <<- counter+1L; paste0("00000000-0000-4000-8000-", sprintf("%012d", counter))}
  clock <- function(value = 1000, instance = "original-page") list(id = "browser-monotonic", unit = "ms", value = as.character(value), instance_id = instance, time_origin_ms = "1700000000000")
  new_run <- function(p = policy) {
    d <- brohn_new_design("Original generated camera fixture", "survey"); d$participant_equipment <- NULL # Historical camera receipt regression.
    info <- brohn_question("Original information screen", "information", "before"); info$required <- FALSE
    d$questions <- list(info); d$camera <- p
    d$consent$required <- FALSE; brohn_validate_design(d)
    s <- brohn_put_entity(store, "study", d$id, d, project_id = "default")
    deployment <- brohn_publish(store, s$id, origin = "sample", quota = 10, alias_required = TRUE)
    started <- .brohn_delivery_start(store, deployment$token, list(consented = TRUE, participant_alias = paste0("ORIGINAL-", uuid()), client_id = uuid(), operation_id = uuid()))
    list(run_id = started$run_id, token = started$access_token, protocol = started$protocol, design = d, deployment = deployment)
  }
  start_request <- function(consented = TRUE) list(capture_id = paste0("camera-", uuid()), consented = consented, clock = clock(),
    mime_type = if (consented) "video/webm;codecs=vp8" else NULL,
    settings = if (consented) list(width = 640, height = 480, frame_rate = 15, audio = FALSE) else NULL,
    reason = if (consented) NULL else "participant_declined", operation_id = uuid())
  chunk_request <- function(id, sequence, bytes, callback = 2500, frames = list()) list(capture_id = id, sequence = sequence,
    data_base64 = gsub("[\r\n]", "", jsonlite::base64_enc(bytes)), sha256 = digest::digest(bytes, algo = "sha256", serialize = FALSE),
    observation = list(callback_ms = as.character(callback), event_timecode_ms = callback-1000, frames = frames, unretained_frame_callbacks = 0L), operation_id = uuid())
  finish_request <- function(id, sequence, bytes, outcome = "completed", end = 4000) list(capture_id = id, final_sequence = sequence, total_bytes = bytes,
    outcome = outcome, container_complete = outcome == "completed", clock = clock(end), reason = if (outcome == "completed") NULL else "original_fixture_interruption", operation_id = uuid())
  run <- new_run(); start <- start_request(); receipt <- .brohn_camera_start(store, run$run_id, run$token, start)
  check("real released run accepts separate camera consent", receipt$status == "recording" && receipt$next_sequence == 1L)
  check("start retry is idempotent", identical(brohn_hash(receipt), brohn_hash(.brohn_camera_start(store, run$run_id, run$token, start))))
  different <- start; different$operation_id <- uuid(); different$clock$value <- "999"
  check("new operation cannot change one run's recorder start", rejects(.brohn_camera_start(store, run$run_id, run$token, different)))
  check("wrong bearer cannot receive camera data", rejects(.brohn_camera_start(store, run$run_id, paste(rep("f", 64), collapse = ""), start)))
  second <- new_run()
  check("another authenticated run cannot address this capture", rejects(.brohn_camera_chunk(store, second$run_id, second$token, chunk_request(start$capture_id, 1L, video))))
  first_bytes <- video[seq_len(257L)]; rest <- video[-seq_len(257L)]
  frame <- list(now_ms = 1100, media_time_s = .1, presentation_time_ms = 1090, expected_display_time_ms = 1110, capture_time_ms = NULL,
    presented_frames = 1L, width = 640L, height = 480L, step_id = NULL, phase = NULL)
  first <- chunk_request(start$capture_id, 1L, first_bytes, 2000, list(frame)); final <- chunk_request(start$capture_id, 2L, rest, 3000)
  check("out-of-order chunks reject before accepting bytes", rejects(.brohn_camera_chunk(store, run$run_id, run$token, final)))
  bad <- first; bad$sha256 <- paste(rep("0", 64), collapse = ""); check("byte hash mismatch rejects", rejects(.brohn_camera_chunk(store, run$run_id, run$token, bad)))
  bad <- first; bad$data_base64 <- paste0("!", bad$data_base64); check("malformed base64 rejects", rejects(.brohn_camera_chunk(store, run$run_id, run$token, bad)))
  accepted <- .brohn_camera_chunk(store, run$run_id, run$token, first)
  check("individual incomplete container chunk can be saved", accepted$acked_sequence == 1L && accepted$total_bytes == 257L)
  retry <- first; retry$operation_id <- uuid(); again <- .brohn_camera_chunk(store, run$run_id, run$token, retry)
  check("lost acknowledgment with new operation safely deduplicates exact bytes and observations", again$acked_sequence == 1L && again$total_bytes == 257L)
  wrong <- retry; wrong$operation_id <- uuid(); wrong$observation$event_timecode_ms <- 123
  check("duplicate sequence cannot alter recorded observations", rejects(.brohn_camera_chunk(store, run$run_id, run$token, wrong)))
  stale <- final; stale$observation$callback_ms <- "1500"
  check("reversing browser callbacks reject", rejects(.brohn_camera_chunk(store, run$run_id, run$token, stale)))
  duplicate_frames <- final; duplicate_frames$observation$frames <- list(frame)
  check("split fragments cannot repeat retained frame callbacks", rejects(.brohn_camera_chunk(store, run$run_id, run$token, duplicate_frames)))
  missing_final <- finish_request(start$capture_id, 2, length(video))
  check("final receipt waits for every declared chunk", rejects(.brohn_camera_finish(store, run$run_id, run$token, missing_final)))
  last <- .brohn_camera_chunk(store, run$run_id, run$token, final)
  check("all chunk bytes and original callback counts are retained", last$acked_sequence == 2L && last$total_bytes == length(video) && brohn_capture(store, start$capture_id)$frame_callbacks == 1L)
  new_clock <- missing_final; new_clock$clock$instance_id <- "new-page"
  check("a new page cannot complete a previous recorder container", rejects(.brohn_camera_finish(store, run$run_id, run$token, new_clock)))
  done <- .brohn_camera_finish(store, run$run_id, run$token, missing_final)
  check("camera transfer completes independently of decoder processing", done$status == "saved" && done$decoding == "separate_processing")
  check("immutable camera ending deduplicates", identical(brohn_hash(done), brohn_hash(.brohn_camera_finish(store, run$run_id, run$token, missing_final))))
  conflicting <- missing_final; conflicting$operation_id <- uuid(); conflicting$outcome <- "withdrawn"; conflicting$reason <- "Changed after final"
  check("terminal outcome cannot be replaced", rejects(.brohn_camera_finish(store, run$run_id, run$token, conflicting)))
  check("required camera transfer guard passes after saved recording", brohn_camera_completion(store, run$run_id)$eligible)
  job <- Filter(function(j) j$operation == "assemble_capture" && j$request$capture_id == start$capture_id, brohn_list_jobs(store))[[1L]]
  check("completion queues exactly one assembly job", length(Filter(function(j) j$operation == "assemble_capture", brohn_list_jobs(store))) == 1L)
  claim <- brohn_claim_job(store, "camera-qa", lease_seconds = 60)
  check("supervised job claims the camera assembly", identical(claim$id, job$id))
  brohn_process_job(store, claim, timeout_seconds = 90)
  completed <- brohn_get_job(store, job$id)
  if (completed$status != "succeeded") stop("Actual camera assembly failed: ", brohn_json(completed$error), call. = FALSE)
  dataset <- brohn_get_entity(store, "dataset", completed$result$dataset_id); publication <- brohn_get_entity(store, "camera_capture", start$capture_id)
  check("actual child decoder creates linked immutable video dataset", dataset$body$source_provenance$capture_id == start$capture_id && publication$body$assembly$decoder$decoded)
  check("source bytes survive exactly across assembly and scratch cleanup", identical(readBin(brohn_object_path(store, dataset$body$source$hash), "raw", n = length(video)), video))
  check("decoded frame counts and encoded PTS remain explicit", publication$body$assembly$decoder$video_frames == 30L && publication$body$assembly$decoder$timestamp_support &&
    publication$body$assembly$decoder$encoded_alignment_to_browser_clock == "not_established")
  check("source keeps frozen study identity and sample origin", dataset$body$study_id == run$design$id && dataset$body$source_provenance$design_hash == run$protocol$design_hash && dataset$body$origin == "sample")
  check("report publishes no scratch paths", !grepl("source_path|observation_path|frame_manifest_path|/scratch/", brohn_json(publication$body)))
  check("camera publication uses parent-owned native guards",identical(publication$body$processing$publication$mode,"staged-windows-parent-read-seal/1.0"))
  frozen_camera<-brohn_read_json_file(brohn_object_path(store,publication$body$result_object$hash))
  check("standalone camera export retains exact complete artifact handles",identical(brohn_hash(frozen_camera$artifacts),brohn_hash(publication$body$artifacts)))
  check("none profile does not queue automatic geometry", !any(vapply(brohn_list_jobs(store), function(j) j$operation == "analyse_dataset", logical(1))))
  for (a in publication$body$artifacts) check(paste("immutable artifact survives:", a$kind), file.exists(brohn_object_path(store, a$hash)))
  # Optional decision is explicit and separate from no decision.
  optional <- policy; optional$required <- FALSE; opted <- new_run(optional)
  check("missing optional decision is not implicit permission or decline", !brohn_camera_completion(store, opted$run_id)$eligible)
  decline <- start_request(FALSE); .brohn_camera_start(store, opted$run_id, opted$token, decline)
  check("explicit optional decline permits questionnaire completion", brohn_camera_completion(store, opted$run_id)$eligible && brohn_capture(store, decline$capture_id)$total_bytes == 0)
  mandatory <- new_run(); declined <- start_request(FALSE); .brohn_camera_start(store, mandatory$run_id, mandatory$token, declined)
  check("required-camera decline cannot satisfy completion", !brohn_camera_completion(store, mandatory$run_id)$eligible)
  interrupted <- new_run(); interrupted_start <- start_request(); .brohn_camera_start(store, interrupted$run_id, interrupted$token, interrupted_start)
  .brohn_camera_chunk(store, interrupted$run_id, interrupted$token, chunk_request(interrupted_start$capture_id, 1L, first_bytes))
  reload <- finish_request(interrupted_start$capture_id, 1L, length(first_bytes), "interrupted", 1000)
  reload$reason <- "page_reload_recording_end_unobserved"
  .brohn_camera_finish(store, interrupted$run_id, interrupted$token, reload)
  check("reload sentinel retains partial bytes without invented ending time", !brohn_camera_completion(store, interrupted$run_id)$eligible &&
    brohn_capture(store, interrupted_start$capture_id)$total_bytes == length(first_bytes))
  partial_job <- Filter(function(j) j$operation == "assemble_capture" && j$request$capture_id == interrupted_start$capture_id, brohn_list_jobs(store))[[1L]]
  partial <- brohn_claim_job(store, "camera-qa", lease_seconds = 60); stopifnot(partial$id == partial_job$id)
  brohn_process_job(store, partial, timeout_seconds = 90)
  partial_done <- brohn_get_job(store, partial$id); stopifnot(partial_done$status == "succeeded")
  partial_dataset <- brohn_get_entity(store, "dataset", partial_done$result$dataset_id)
  check("partial unplayable original source remains downloadable and distinct", partial_dataset$body$status == "needs_mapping" && !partial_dataset$body$source_provenance$decoder$decoded &&
    identical(readBin(brohn_object_path(store, partial_dataset$body$source$hash), "raw", n = length(first_bytes)), first_bytes))
  steps <- function(r, first = 2000) {
    events <- list(); when <- first
    emit <- function(type, step = NULL, time = when) {
      events[[length(events)+1L]] <<- list(sequence = length(events)+1L, id = uuid(), type = type,
        step_id = if (is.null(step)) NULL else step$id, stimulus_id = if (is.null(step)) NULL else step$stimulus_id,
        condition_id = if (is.null(step)) NULL else step$condition_id, question_id = if (is.null(step)) NULL else step$question$id,
        phase = if (is.null(step)) "complete" else step$phase, clock = clock(time), payload = if (is.null(step)) list(outcome = "completed") else list(origin = "original_fixture"))
    }
    for (step in r$protocol$timeline) {emit("step_started", step); when <- when+100; emit("step_finished", step); when <- when+100}
    emit("run_finished", time = max(5000, when+100))
    .brohn_delivery_receive(store, r$run_id, r$token, list(events = events, operation_id = uuid()))
    list(outcome = "completed", final_sequence = length(events), operation_id = uuid())
  }
  final_study <- steps(run)
  check("recording coverage excludes the later run_finished event", brohn_camera_completion(store, run$run_id)$eligible)
  saved_run <- .brohn_delivery_finish(store, run$run_id, run$token, final_study)
  check("actual final study receipt requires and retains camera support", saved_run$status == "saved" && brohn_run(store, run$run_id)$completion_status == "completed")
  for (j in Filter(function(j) j$status == "queued", brohn_list_jobs(store))) brohn_cancel_job(store, j$id)
  # A recording may be transferred completely while failing study timing support.
  late_start <- start_request(); .brohn_camera_start(store, second$run_id, second$token, late_start)
  .brohn_camera_chunk(store, second$run_id, second$token, chunk_request(late_start$capture_id, 1L, video, 3000))
  .brohn_camera_finish(store, second$run_id, second$token, finish_request(late_start$capture_id, 1L, length(video)))
  outside_bounds <- steps(second, first = 4500)
  check("study clocks outside recording bounds cannot claim camera coverage", !brohn_camera_completion(store, second$run_id)$eligible &&
    rejects(.brohn_delivery_finish(store, second$run_id, second$token, outside_bounds)) && brohn_run(store, second$run_id)$completion_status == "in_progress")
  for (j in Filter(function(j) j$status == "queued", brohn_list_jobs(store))) brohn_cancel_job(store, j$id)
  automatic_policy <- policy; automatic_policy$analysis_profile <- "face_geometry_v1"
  automatic <- new_run(automatic_policy); auto_start <- start_request(); .brohn_camera_start(store, automatic$run_id, automatic$token, auto_start)
  .brohn_camera_chunk(store, automatic$run_id, automatic$token, chunk_request(auto_start$capture_id, 1L, video, 3000))
  .brohn_camera_finish(store, automatic$run_id, automatic$token, finish_request(auto_start$capture_id, 1L, length(video)))
  auto_job <- brohn_claim_job(store, "camera-qa", lease_seconds = 60); brohn_process_job(store, auto_job, timeout_seconds = 90)
  stopifnot(brohn_get_job(store, auto_job$id)$status == "succeeded")
  check("decoded capture cannot start geometry before the study completes", !any(vapply(brohn_list_jobs(store), function(j) j$operation == "analyse_dataset", logical(1))))
  auto_final <- steps(automatic); .brohn_delivery_finish(store, automatic$run_id, automatic$token, auto_final)
  .brohn_delivery_finish(store, automatic$run_id, automatic$token, auto_final); brohn_queue_capture_analysis(store, automatic$run_id)
  geometry <- Filter(function(j) j$operation == "analyse_dataset", brohn_list_jobs(store))
  check("completed study plus decoded requested profile queues geometry once", length(geometry) == 1L &&
    geometry[[1L]]$request$dataset_id == paste0("dataset-", auto_start$capture_id))
  for (j in Filter(function(j) j$status == "queued", brohn_list_jobs(store))) brohn_cancel_job(store, j$id)
  # A cancelled attempt must not publish even complete, correctly hashed bytes.
  fenced <- new_run(); fence_start <- start_request(); .brohn_camera_start(store, fenced$run_id, fenced$token, fence_start)
  .brohn_camera_chunk(store, fenced$run_id, fenced$token, chunk_request(fence_start$capture_id, 1L, video, 3000))
  .brohn_camera_finish(store, fenced$run_id, fenced$token, finish_request(fence_start$capture_id, 1L, length(video)))
  fence_job <- brohn_claim_job(store, "camera-fence-qa", lease_seconds = 60); input <- brohn_capture_input(store, fence_job)
  scratch <- file.path(store$root, "scratch", "camera-fence-qa"); dir.create(scratch, recursive = TRUE)
  assembled <- brohn_assemble_capture(input, scratch)
  identity_paths<-c("R/platform-publication.R","R/platform-capture.R","scripts/workers/publication.py","src/publication_guard.c")
  output <- list(schema = "brohn-analysis-output/1.0", report = assembled,
    code_identity = setNames(lapply(identity_paths,function(path)digest::digest(file=path,algo="sha256")),identity_paths))
  output_path <- file.path(scratch, "result.json"); brohn_write_json_file(output, output_path)
  check("standalone camera manifest retains consent retention and exact frozen study context",
    identical(assembled$camera_assembly$policy, input$capture$start$policy) &&
    identical(assembled$camera_assembly$study$design_hash, input$capture$start$design_hash) &&
    identical(assembled$camera_assembly$study$protocol_hash, input$capture$start$protocol_hash) &&
    assembled$camera_assembly$study$study_revision == input$capture$start$study_revision &&
    identical(assembled$camera_assembly$participant$participant_id, input$capture$start$participant_id))
  substituted <- output; substituted$report$camera_assembly$policy$retention_text <- "Substituted retention policy"
  check("publication rejects a changed policy inside a camera manifest",
    rejects(brohn_publish_capture(store, substituted, scratch, fence_job, input, output_path)))
  brohn_cancel_job(store, fence_job$id)
  check("expired publication fence rejects otherwise valid camera artifacts", rejects(brohn_publish_capture(store, output, scratch, fence_job, input, output_path)) &&
    is.null(brohn_get_entity(store, "dataset", paste0("dataset-", fence_start$capture_id))))
  corrupt_input <- input; corrupt_path <- file.path(root, "same-size-chunk-corruption.bin"); corrupt_bytes <- video
  corrupt_bytes[[length(corrupt_bytes)]] <- as.raw(bitwXor(as.integer(corrupt_bytes[[length(corrupt_bytes)]]), 1L)); writeBin(corrupt_bytes, corrupt_path)
  corrupt_input$chunks[[1L]]$source_path <- corrupt_path
  other_scratch <- file.path(root, "corrupt-attempt"); dir.create(other_scratch)
  check("same-size corrupted chunk rejects before assembly", rejects(brohn_assemble_capture(corrupt_input, other_scratch)))
  retried <- brohn_retry_processing(store, fence_job$id)
  check("cancelled camera assembly retries the identical frozen receipt", retried$operation == "assemble_capture" &&
    identical(retried$request, fence_job$request) && retried$id != fence_job$id)
  retry_claim <- brohn_claim_job(store, "camera-retry-qa", lease_seconds = 60)
  stopifnot(identical(retry_claim$id, retried$id))
  brohn_process_job(store, retry_claim, timeout_seconds = 90)
  check("retried assembly publishes the original source once while the cancelled attempt stays fenced",
    brohn_get_job(store, retried$id)$status == "succeeded" && brohn_get_job(store, fence_job$id)$status == "cancelled" &&
    brohn_get_entity(store, "dataset", paste0("dataset-", fence_start$capture_id))$revision == 1L &&
    rejects(brohn_publish_capture(store, output, scratch, fence_job, input, output_path)))
  # Policy travels with saved design packages; camera participant bytes do not.
  package <- file.path(root, "camera-design.brohn-study.zip"); brohn_export_design(store, run$design$id, package)
  imported <- brohn_import_design(store, package, title = "Reused original camera design")
  check("portable study preserves exact camera policy", identical(brohn_hash(imported$body$camera), brohn_hash(policy)))
  check("camera catalog integrity checks immutable receipts and references", isTRUE(brohn_capture_catalog_integrity(store$con)))
  backup_path <- file.path(root, "camera.brohn-backup"); backup <- brohn_backup_workspace(store, backup_path)
  check("camera snapshot includes extra tables and registered source artifacts", backup$verified && brohn_verify_backup(backup_path)$verified)
  cli_verify <- processx::run(brohn_rscript(), c("--vanilla", "scripts/backup-workspace.R", "verify", "--backup", backup_path),
    env = c("current", R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep)),
    error_on_status = FALSE, timeout = 60000, windows_hide_window = TRUE)
  check("standalone administrative CLI verifies camera-aware backup using selected library", cli_verify$status == 0 &&
    isTRUE(brohn_parse(trimws(cli_verify$stdout))$verified))
  restored_path <- file.path(root, "restored"); restoration <- brohn_restore_workspace(backup_path, restored_path)
  restored <- brohn_open_store(restored_path)
  on.exit(try(brohn_close_store(restored), silent = TRUE), add = TRUE)
  check("restore preserves camera decisions and full partial/final chunk totals", identical(brohn_hash(brohn_capture(restored, start$capture_id)), brohn_hash(brohn_capture(store, start$capture_id))) &&
    brohn_capture(restored, interrupted_start$capture_id)$total_bytes == length(first_bytes))
  check("restored camera objects retain exact bytes", identical(readBin(brohn_object_path(restored, dataset$body$source$hash), "raw", n = length(video)), video))
  triggers <- DBI::dbGetQuery(restored$con, "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'camera_%'")$name
  check("camera immutability triggers survive restore", all(c("camera_start_immutable", "camera_terminal_immutable", "camera_chunks_no_update", "camera_chunks_no_delete") %in% triggers))
  check("restore rotates participant credentials and pauses capture operations", brohn_workspace_execution_status(restored)$paused &&
    rejects(.brohn_delivery_authorize(restored, run$run_id, run$token)))
  brohn_close_store(restored)
  cat("PASS: ", checks, " camera assertions (real release, authenticated receipts, loss/retry, single-container assembly, immutable artifacts, decoder and partial retention)\n", sep = "")
})
