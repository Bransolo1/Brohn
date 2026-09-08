source("R/platform-load.R"); brohn_load(ui = FALSE)
source("R/platform-stream-curation.R")
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Stream curation QA failed: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-stream-curation-qa-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace")); brohn_initialise_library(store)
  on.exit({brohn_close_store(store); actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-stream-curation-qa-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)}, add = TRUE)
  fixture <- paste("import importlib.util,json,sys,copy,math; from pathlib import Path",
    "spec=importlib.util.spec_from_file_location('original_fixture','tests/workers/stream_extract.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)",
    "root=Path(sys.argv[1]); bundle=m.bundle_fixture(); s=bundle['streams'][0]",
    "second=[{'timestamp':str(1000+i*10000000),'values':[10*math.sin(2*math.pi*20*i/100)]} for i in range(1000)]; second[0]['reset']=True; s['samples']+=second",
    "(root/'original-two-spectra.json').write_text(json.dumps(bundle)); missing=copy.deepcopy(bundle)",
    "for row in missing['streams'][0]['samples']: row['values']=[None]",
    "(root/'original-missing.json').write_text(json.dumps(missing))", sep = "\n")
  processx::run(.brohn_port_python(), c("-B", "-c", fixture, root), timeout = 30000, windows_hide_window = TRUE)
  original <- brohn_ingest_dataset(store, file.path(root, "original-two-spectra.json"), "Original two spectra and clock reset", modality = "multimodal", origin = "sample")
  accepted <- brohn_curate_dataset(store, original$id, list(origin_statement = "Original generator: same synthetic person/visit, 10 Hz then clock reset and 20 Hz; no physical device.", clock_policy = "preserve_only"), original$revision)
  run_job <- function(job) {
    force(job)
    claim <- brohn_claim_job(store, "stream-curation-qa", lease_seconds = 90)
    stopifnot(claim$id == job$id)
    brohn_process_job(store, claim, timeout_seconds = 90)
    done <- brohn_get_job(store, job$id)
    if (done$status != "succeeded") stop("Actual supervised job failed: ", brohn_json(done$error), call. = FALSE)
    done
  }
  imported <- run_job(brohn_queue_multistream(store, accepted$id))
  stream <- brohn_streams(store, import_id = imported$result$import_id)[[1L]]
  selection <- list(schema = "brohn-stream-selection/1.0", channel_ids = list("eeg"), modality = "eeg", unit = "V", sampling_rate = 100,
    participant_id = NULL, session_id = NULL, origin_statement = "Original generator with source participant/session identities preserved.",
    unit_rationale = "Source generator explicitly declares microvolts; convert to volts using 1e-6.", confirm_source_units = TRUE, confirm_boundaries = TRUE, run_analysis = TRUE)
  check("reviewed scalar channel declaration validates", !rejects(brohn_validate_stream_selection(stream$body, selection)))
  bad <- selection; bad$channel_ids <- list("missing"); check("foreign channel cannot be selected", rejects(brohn_queue_stream_curation(store, stream$id, bad)))
  bad <- selection; bad$sampling_rate <- 101; check("sampling rate cannot replace recorded declaration", rejects(brohn_queue_stream_curation(store, stream$id, bad)))
  bad <- selection; bad$unit_rationale <- ""; check("unit rationale is required before curation", rejects(brohn_queue_stream_curation(store, stream$id, bad)))
  bad <- stream$body; bad$manifest$channels[[1]]$value_type <- "boolean"; check("Boolean channel cannot be curated as EEG", rejects(brohn_validate_stream_selection(bad, selection)))
  bad <- stream$body; bad$manifest$channels[[1]]$scale <- "2"; check("unapplied calibration cannot be bypassed by manual units", rejects(brohn_validate_stream_selection(bad, selection)))
  job <- brohn_queue_stream_curation(store, stream$id, selection)
  check("same pinned stream selection deduplicates", job$id == brohn_queue_stream_curation(store, stream$id, selection)$id)
  amended <- accepted$body$metadata; amended$origin_statement <- "Later raw-source note amendment after curation queued."
  later <- brohn_curate_dataset(store, accepted$id, amended, accepted$revision)
  done <- run_job(job)
  curated <- brohn_get_entity(store, "stream_curation", done$result$curation_id)
  dataset <- brohn_get_entity(store, "dataset", done$result$dataset_id)
  check("requested standard analysis is queued automatically with frozen parameters", !is.null(done$result$analysis_job_id) && identical(curated$body$analysis_job_id, done$result$analysis_job_id) &&
    brohn_get_job(store, done$result$analysis_job_id)$status == "queued" && dataset$body$metadata$parameters$recipe == "eeg-welch-channel/1.0")
  check("actual supervised extraction publishes exactly one derived dataset", length(Filter(function(r) identical(r$body$source_provenance$acquisition, "curated_stream"), brohn_list_entities(store, "dataset"))) == 1L)
  check("two clock segments preserve one original person and visit", dataset$body$metadata$segment_column == "brohn_segment_id" && curated$body$extraction$quality$segment_count == 2L &&
    length(unique(vapply(curated$body$extraction$segments, function(s) s$group$participant_id, character(1)))) == 1L &&
    length(unique(vapply(curated$body$extraction$segments, function(s) s$group$session_id, character(1)))) == 1L)
  check("clock boundaries do not invent exposures or condition mappings", is.null(dataset$body$metadata$exposure_column) && is.null(dataset$body$metadata$condition_column))
  check("source lineage pins pre-amendment raw revision and unchanged stream bytes", curated$body$lineage$raw_dataset_revision == accepted$revision &&
    curated$body$lineage$raw_dataset_hash == brohn_hash(accepted$body) && brohn_get_entity(store, "dataset", accepted$id)$revision == later$revision)
  check("all original source artifacts remain referenced and verified", length(curated$body$lineage$original_stream_artifacts) == 3L &&
    all(vapply(curated$body$lineage$original_stream_artifacts, function(a) file.exists(brohn_object_path(store, a$hash)), logical(1))) &&
    file.exists(brohn_object_path(store, curated$body$lineage$raw_source$hash)))
  check("curated sample origin cannot become physical device evidence", dataset$body$origin == "sample" && identical(curated$body$extraction$quality$synchronized, FALSE))
  check("included and excluded counts cover the complete stream", curated$body$extraction$quality$source_rows == 2000L && curated$body$extraction$quality$included_rows == 2000L && curated$body$extraction$quality$excluded_rows == 0L)
  values <- brohn_read_table(brohn_object_path(store, dataset$body$source$hash), "csv")
  check("CSV retains large exact native timestamp text after reset", values$source_timestamp[[1]] == "9007199254740993" && values$source_timestamp[[1001]] == "1000" &&
    values$brohn_time_s[[1]] == "0E-9" && values$brohn_time_s[[1001]] == "0E-9")
  check("source row order and independent segment identity are explicit", identical(as.numeric(values$source_sequence), as.numeric(1:2000)) && values$brohn_segment_id[[1]] != values$brohn_segment_id[[1001]])
  decisions <- Filter(function(a) a$kind == "curation_decisions_jsonl", curated$body$extraction$artifacts)[[1L]]
  check("full decision artifact remains after scratch cleanup", brohn_interchange_jsonl_count(brohn_object_path(store, decisions$hash)) == 2000 && !length(setdiff(list.dirs(file.path(store$root,"scratch"),recursive=FALSE,full.names=FALSE),"publication")))
  check("curation uses parent-owned staged publication",identical(curated$body$processing$publication$mode,"staged-windows-parent-read-seal/1.0"))
  frozen_curation<-brohn_read_json_file(brohn_object_path(store,curated$body$result_object$hash))
  check("dependent job identity agrees with the prebuilt immutable export",identical(frozen_curation$analysis_job_id,curated$body$analysis_job_id) &&
    identical(frozen_curation$analysis_job_id,done$result$analysis_job_id))
  check("curation has verifiable source identities and no scratch paths", all(c("R/platform-stream-curation.R", "scripts/workers/stream_extract.py", "scripts/analysis-worker.R") %in% names(curated$body$processing$code_hashes)) && !grepl('"path"|/scratch/', brohn_json(curated$body)))
  analysis_done <- run_job(brohn_queue_dataset(store, dataset$id))
  report <- brohn_get_entity(store, "report", analysis_done$result$report_id)
  features <- report$body$analysis$features
  peaks <- Filter(function(f) identical(f$name, "psd_peak_frequency"), features)
  powers <- Filter(function(f) identical(f$name, "psd_total_power"), features)
  check("actual curated EEG analysis finds independent 10 Hz and 20 Hz spectra", length(peaks) == 2L && identical(vapply(peaks, function(f) f$value, numeric(1)), c(10,20)))
  check("actual EEG powers match independent amplitude-squared-over-two oracle", length(powers) == 2L && abs(powers[[1]]$value-200) < 1e-6 && abs(powers[[2]]$value-50) < 1e-6)
  check("scientific reports retain source segment identities without changing participants", peaks[[1]]$group$segment_id != peaks[[2]]$group$segment_id &&
    peaks[[1]]$group$participant_id == "original-person" && peaks[[2]]$group$participant_id == "original-person" && peaks[[1]]$group$session_id == peaks[[2]]$group$session_id)

  # Fence and corruption checks use their own unpublished attempt and do not
  # mutate registered source objects or create another candidate dataset.
  retry <- brohn_queue_stream_curation(store, stream$id, selection, force = TRUE)
  claim <- brohn_claim_job(store, "stream-curation-fence", lease_seconds = 90)
  input <- brohn_stream_curation_input(store, claim)
  scratch <- file.path(store$root, "scratch", "original-curation-fence"); dir.create(scratch)
  identity_paths<-c("R/platform-publication.R","R/platform-stream-curation.R","scripts/workers/publication.py","src/publication_guard.c")
  result <- list(schema = "brohn-analysis-output/1.0", report = brohn_analyse_stream_curation(input, scratch),
    code_identity = setNames(lapply(identity_paths,function(path)digest::digest(file=path,algo="sha256")),identity_paths))
  result_path <- file.path(scratch, "result.json"); brohn_write_json_file(result, result_path)
  brohn_cancel_job(store, claim$id)
  before <- length(brohn_list_entities(store, "stream_curation"))
  check("cancelled publication fence prevents otherwise valid derived objects", rejects(brohn_publish_stream_curation(store, result, scratch, claim, input, result_path)) && length(brohn_list_entities(store, "stream_curation")) == before)
  corrupt <- file.path(root, "corrupt-canonical.jsonl"); writeLines("{}", corrupt); bad <- input; bad$source_path <- corrupt
  other <- file.path(root, "bad-attempt"); dir.create(other)
  check("corrupt canonical bytes fail before publication", rejects(brohn_analyse_stream_curation(bad, other)))
  empty_source <- brohn_ingest_dataset(store, file.path(root, "original-missing.json"), "Original all-missing source", modality = "multimodal", origin = "sample")
  empty_source <- brohn_curate_dataset(store, empty_source$id, accepted$body$metadata, empty_source$revision)
  missing_import <- run_job(brohn_queue_multistream(store, empty_source$id))
  missing_stream <- brohn_streams(store, import_id = missing_import$result$import_id)[[1L]]
  missing_done <- run_job(brohn_queue_stream_curation(store, missing_stream$id, selection))
  missing_curation <- brohn_get_entity(store, "stream_curation", missing_done$result$curation_id)
  check("unusable curation cannot automatically queue a scientific analysis", is.null(missing_done$result$analysis_job_id))
  check("no usable source publishes explicit exclusions and no empty analysis dataset", is.null(missing_done$result$dataset_id) && missing_curation$body$status == "needs_attention" && missing_curation$body$extraction$quality$excluded_rows == 2000)
  source_hash <- dataset$body$source$hash; curation_hash <- brohn_hash(curated$body); report_hash <- brohn_hash(report$body)
  brohn_close_store(store); store <- brohn_open_store(file.path(root, "workspace"))
  check("curated source and scientific report reopen unchanged", brohn_hash(brohn_get_entity(store, "stream_curation", curated$id)$body) == curation_hash && brohn_hash(brohn_get_entity(store, "report", report$id)$body) == report_hash)
  download <- file.path(root, "full-curated.csv"); brohn_copy_object_download(store, source_hash, download)
  check("full derived CSV downloads exact bytes after reopen", digest::digest(file = download, algo = "sha256") == source_hash && file.access(download, 2) == 0L)
  for (module in c("shell", "data-views", "app", "stream-curation-views")) source(paste0("R/platform-", module, ".R"), encoding = "UTF-8")
  ui_server <- function(input, output, session) {
    state <- shiny::reactiveValues(page = "dataset", dataset_id = accepted$id, error = NULL, status = NULL, version = 0L)
    attempt <- function(fn) {state$error <- NULL; tryCatch(fn(), error = function(e) {state$error <- conditionMessage(e); NULL})}
    message <- function(text) state$status <- text
    refresh <- function() state$version <- state$version+1L
    api <- brohn_install_stream_curation_ui(input, output, session, store, state, attempt, message, refresh, function(fn) fn())
  }
  manual_job <- NULL
  shiny::testServer(ui_server, {
    command <- list(stream_id = stream$id, revision = stream$revision, hash = brohn_hash(stream$body))
    session$setInputs(multistream_stream_id = stream$id, open_stream_curation = command)
    context <- api$context()
    check("actual researcher UI opens a source-pinned curation draft", identical(context$stream_id, stream$id) && identical(context$hash, brohn_hash(stream$body)))
    session$setInputs(stream_curation_form = context$id, stream_curation_channels = "eeg", stream_curation_modality = "eeg", stream_curation_unit = "V",
      stream_curation_unit_rationale = "", stream_curation_origin = "Original manual UI source and identity review.", stream_curation_participant = "",
      stream_curation_session = "", stream_curation_units_confirmed = TRUE, stream_curation_boundaries_confirmed = TRUE, stream_curation_run_analysis = FALSE)
    check("standard recipe preview exposes effective settings and descriptive scope", grepl("2-second Hann", output$stream_curation_recipe$html, fixed = TRUE) && grepl("condition effects require", output$stream_curation_recipe$html, fixed = TRUE))
    session$setInputs(save_stream_curation = list(editor_id = context$id))
    check("UI will not queue an unexplained unit declaration", !is.null(state$error) && !is.null(api$context()))
    session$setInputs(cancel_stream_curation = list(editor_id = context$id))
    check("Cancel discards the source curation draft", is.null(api$context()))
    session$setInputs(save_stream_curation = list(editor_id = context$id))
    check("late Prepare after Cancel cannot queue source changes", !is.null(state$error))
    session$setInputs(open_stream_curation = command); current <- api$context()
    session$setInputs(cancel_stream_curation = list(editor_id = context$id))
    check("old Cancel cannot close a newer curation dialog", !is.null(state$error) && identical(api$context()$id, current$id))
    session$setInputs(stream_curation_form = context$id, save_stream_curation = list(editor_id = current$id))
    check("stale form identity cannot prepare a new draft", !is.null(state$error))
    session$setInputs(stream_curation_form = current$id, stream_curation_unit_rationale = "Original generator units uV explicitly reviewed; conversion to V requested.")
    session$setInputs(save_stream_curation = list(editor_id = current$id))
    check("manual preparation choice is saved explicitly without a second analysis decision", is.null(state$error) && is.null(api$context()))
    queued <- Filter(function(j) j$operation == "extract_stream" && j$status == "queued", brohn_list_jobs(store))
    check("actual UI queue preserves unchecked analysis and source identity", length(queued) == 1L && identical(queued[[1]]$request$selection$run_analysis, FALSE) && is.null(queued[[1]]$request$selection$participant_id))
    manual_job <<- queued[[1L]]
    session$setInputs(review_stream_curation = curated$id)
    check("source review resolves the complete immutable curation", is.null(state$error) && identical(api$reviewed()$body$result_object$hash, curated$body$result_object$hash))
    state$dataset_id <- dataset$id
    check("derived Data can review its original curation evidence", identical(api$reviewed()$id, curated$id))
    state$dataset_id <- empty_source$id
    check("stale review download cannot follow navigation to another dataset", rejects(api$reviewed()))
    state$page <- "studies"
    session$setInputs(open_stream_curation = command)
    check("stale source command after navigation cannot open a curation draft", !is.null(state$error))
  })
  manual <- run_job(manual_job)
  check("unchecked standard analysis publishes only a prepared dataset", !is.null(manual$result$dataset_id) && is.null(manual$result$analysis_job_id) &&
    !any(vapply(brohn_list_jobs(store), function(j) j$operation == "analyse_dataset" && identical(j$request$dataset_id, manual$result$dataset_id), logical(1))))
  check("derived Data exposes original recording and full curation review", grepl("Open original recording", as.character(brohn_curated_stream_dataset_ui(store, dataset)), fixed = TRUE) &&
    grepl("Review curation decisions", as.character(brohn_curated_stream_dataset_ui(store, dataset)), fixed = TRUE))
  cat(sprintf("PASS: %d stream curation assertions (supervised raw import, explicit curation, segmented EEG oracle, immutable artifacts, fences and missingness)\n", checks))
})
