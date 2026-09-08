# Actual saved MaxDiff import pipeline and production Shiny mapping guards.
# --mapping-only executes no scientific child and leaves no queued work behind.
source("R/platform-load.R"); brohn_load(ui = TRUE)
local({
  checks <- 0L
  check <- function(name, value) {
    if (!isTRUE(value)) stop("MaxDiff platform import QA: ", name, call. = FALSE)
    checks <<- checks + 1L
  }
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  near <- function(a, b) is.numeric(a) && length(a) == 1L && is.finite(a) && abs(a-b) < 1e-8
  root <- tempfile("brohn-maxdiff-import-platform-"); dir.create(root)
  root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace")); brohn_initialise_library(store)
  on.exit({
    brohn_close_store(store)
    resolved <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(resolved), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")),
      grepl("^brohn-maxdiff-import-platform-", basename(resolved)))
    unlink(resolved, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  exercise <- brohn_maxdiff_new(id = "original-platform-choice")
  exercise$items <- head(exercise$items, 3L)
  exercise$sets <- list(list(id = "original-platform-set", item_ids = as.list(brohn_ids(exercise$items))))
  other <- exercise; other$id <- "other-original-choice"; other$title <- "Other original exercise"
  design <- brohn_new_design("Original MaxDiff import platform reference", "survey", id = "original-platform-study")
  design$maxdiff <- list(exercise, other)
  brohn_validate_design(design)
  study <- brohn_put_entity(store, "study", design$id, design)
  pairs <- list(c(1L,2L), c(1L,3L), c(2L,1L), c(2L,3L), c(3L,1L), c(3L,2L))
  rows <- lapply(seq_along(pairs), function(i) list(id = paste0("original-platform-response-", i),
    participant_id = "original-person", participant_linkage = TRUE, session_id = "original-visit",
    exposure_id = paste0("original-platform-exposure-", i), design_hash = brohn_hash(exercise), set_id = exercise$sets[[1L]]$id,
    item_order = if (i %% 2L) exercise$sets[[1L]]$item_ids else rev(exercise$sets[[1L]]$item_ids),
    presented = TRUE, status = "answered", best_id = paste0("item-", pairs[[i]][[1L]]),
    worst_id = paste0("item-", pairs[[i]][[2L]]), missing_reason = NULL))
  omitted <- rows[[1L]]; omitted$id <- "original-partial"; omitted$exposure_id <- "original-partial-exposure"
  omitted$status <- "missing"; omitted["worst_id"] <- list(NULL); omitted$missing_reason <- "Original partial response retained"
  unpresented <- omitted; unpresented$id <- "original-not-reached"; unpresented$exposure_id <- "original-not-reached-exposure"
  unpresented["best_id"] <- list(NULL); unpresented$presented <- FALSE; unpresented$status <- "not_presented"
  unpresented$missing_reason <- "Original set not reached"
  rows <- c(rows, list(omitted, unpresented))
  other_row <- rows[[1L]]; other_row$id <- "other-original-response"; other_row$design_hash <- brohn_hash(other)
  original_source <- list(hash = strrep("a", 64L), origin = "sample", id = "original-source-ledger", revision = 1L)
  originals <- list(brohn_maxdiff_analysis(exercise, rows, original_source), brohn_maxdiff_analysis(other, list(other_row), original_source))
  csv <- file.path(root, "original-brohn-multiple-exercise-export.csv")
  brohn_export_report_csv(list(analysis = list(choice_tasks = originals)), csv)
  source_hash <- digest::digest(file = csv, algo = "sha256")
  table <- brohn_read_table(csv, "csv", 20000L)
  metadata <- list(exercise_id = exercise$id,
    origin_statement = "Original synthetic six-pair arithmetic reference with a partial, an unpresented set and another exercise; no physical participant recording.",
    participant_column = "participant_id", session_column = "session_id", exposure_column = "exposure_id",
    design_hash_column = "design_hash", set_column = "set_id", item_order_column = "item_order", presented_column = "presented",
    status_column = "status", best_column = "best_id", worst_column = "worst_id", missing_reason_column = "missing_reason",
    participant_linkage_column = "participant_linkage", exercise_column = "exercise_id", origin_column = "origin")
  ingested <- brohn_ingest_dataset(store, csv, "Original mixed-exercise CSV", modality = "maxdiff", origin = "sample")
  check("real Brohn multi-exercise CSV is retained unchanged and needs mapping", nrow(table) == 9L && ingested$body$status == "needs_mapping" &&
    ingested$body$source$hash == source_hash && digest::digest(file = brohn_object_path(store, source_hash), algo = "sha256") == source_hash)
  check("unconfirmed input cannot be analysed", rejects(brohn_queue_dataset(store, ingested$id)))
  check("explicit saved study revision is required before any mapping write", rejects(brohn_curate_dataset(store, ingested$id, metadata, ingested$revision, study$id)) &&
    brohn_get_entity(store, "dataset", ingested$id)$revision == ingested$revision)
  foreign <- metadata; foreign$exercise_id <- "exercise-not-in-study"
  check("foreign exercise is rejected before saving accepted status", rejects(brohn_curate_dataset(store, ingested$id, foreign, ingested$revision, study$id, study$revision)) &&
    brohn_get_entity(store, "dataset", ingested$id)$body$status == "needs_mapping")
  wrong_origin <- brohn_ingest_dataset(store, csv, "Synthetic origin rejection fixture", modality = "maxdiff", origin = "imported")
  check("synthetic exercise cannot acquire imported origin through curation", rejects(brohn_curate_dataset(store, wrong_origin$id, metadata, wrong_origin$revision, study$id, study$revision)) &&
    brohn_get_entity(store, "dataset", wrong_origin$id)$revision == wrong_origin$revision)

  # Drive the production handler. testServer provides a real Shiny reactive
  # session, while no processing service runs against this owned workspace.
  ui_source <- brohn_ingest_dataset(store, csv, "Original UI mapping fixture", modality = "maxdiff", origin = "sample")
  ui_other <- brohn_ingest_dataset(store, csv, "Original other UI mapping fixture", modality = "maxdiff", origin = "sample")
  # testServer accepts only the three Shiny formals for a plain server. Bind
  # its fourth configuration argument without replacing the production body.
  actual_server <- brohn_server
  formals(actual_server) <- formals(brohn_server)[c("input", "output", "session")]
  environment(actual_server) <- list2env(list(store_root = store$root), parent = environment(brohn_server))
  shiny::testServer(actual_server, {
    input_values <- stats::setNames(metadata, paste0("map_md_", names(metadata)))
    names(input_values)[names(input_values) == "map_md_origin_statement"] <- "map_origin"
    input_values <- c(input_values, list(map_unit = "stale-uV", map_values = "stale-signal", map_time = "stale-time",
      map_study = study$id, map_study_revision = "current", accept_dataset = 0L))
    do.call(session$setInputs, input_values)
    state$page <- "dataset"; state$dataset_id <- ui_source$id; session$flushReact()
    session$setInputs(dataset_form_identity = paste(ui_source$id, ui_source$revision, sep = ":"))
    session$flushReact()
    mapped <- shiny::isolate(brohn_dataset_base_mapping(input, ui_source$body))
    check("MaxDiff mapping ignores stale physiology inputs", identical(mapped, metadata))
    resolved <- shiny::isolate(brohn_maxdiff_mapping_study(store, ui_source, input))
    identity <- brohn_maxdiff_mapping_identity(ui_source, resolved)
    check("current selector resolves to a concrete validated study revision", resolved$revision == study$revision && resolved$id == study$id &&
      grepl(brohn_hash(study$body), identity, fixed = TRUE))
    exercise_ui <- output$maxdiff_mapping_exercise
    check("actual reactive exercise selector contains both frozen choices and hash identity", grepl("maxdiff_mapping_design_identity", exercise_ui$html, fixed = TRUE) &&
      grepl(exercise$id, exercise_ui$html, fixed = TRUE) && grepl(other$id, exercise_ui$html, fixed = TRUE) && grepl(identity, exercise_ui$html, fixed = TRUE))
    session$setInputs(maxdiff_mapping_design_identity = "stale-design-identity", accept_dataset = 1L)
    check("actual accept handler rejects an unmatched design identity", grepl("study version changed", state$error, fixed = TRUE) &&
      brohn_get_entity(store, "dataset", ui_source$id)$revision == ui_source$revision && nrow(DBI::dbGetQuery(store$con, "SELECT id FROM jobs")) == 0L)

    # An external valid draft edit while 'current' remains selected invalidates
    # the original hash rather than silently rebinding imported responses.
    ui_edit <- design; ui_edit$title <- "Later draft title from another editor"
    edited_study <- brohn_save_study(store, ui_edit, study$revision)
    session$setInputs(maxdiff_mapping_design_identity = identity, accept_dataset = 2L)
    check("stale current-study form is rejected after external revision change", grepl("study version changed", state$error, fixed = TRUE) &&
      brohn_get_entity(store, "dataset", ui_source$id)$revision == ui_source$revision)
    session$setInputs(map_study_revision = as.character(study$revision), maxdiff_mapping_design_identity = identity, accept_dataset = 3L)
    saved <- brohn_get_entity(store, "dataset", ui_source$id)
    jobs <- brohn_list_jobs(store)
    check("explicit original saved revision is accepted and immediately queued once", is.null(state$error) && saved$revision == ui_source$revision+1L &&
      saved$body$study_revision == study$revision && saved$body$study_id == study$id && length(jobs) == 1L && jobs[[1L]]$operation == "analyse_dataset")
    check("accepted metadata contains exact selected exercise and no signal columns", brohn_hash(saved$body$metadata) == brohn_hash(metadata) &&
      jobs[[1L]]$request$study_hash == brohn_hash(design) && jobs[[1L]]$request$dataset_revision == saved$revision)
    session$setInputs(accept_dataset = 4L)
    check("replayed stale dataset form cannot overwrite accepted revision or enqueue again", grepl("dataset mapping changed", state$error, fixed = TRUE) &&
      brohn_get_entity(store, "dataset", ui_source$id)$revision == saved$revision && length(brohn_list_jobs(store)) == 1L)
    brohn_cancel_job(store, jobs[[1L]]$id)

    state$dataset_id <- ui_other$id; session$flushReact()
    session$setInputs(accept_dataset = 5L)
    check("late old-dataset inputs cannot save the newly navigated source", grepl("dataset mapping changed", state$error, fixed = TRUE) &&
      brohn_get_entity(store, "dataset", ui_other$id)$revision == ui_other$revision)
    session$setInputs(dataset_form_identity = paste(ui_other$id, ui_other$revision, sep = ":"), map_study_revision = "current")
    new_identity <- brohn_maxdiff_mapping_identity(ui_other, edited_study)
    session$setInputs(maxdiff_mapping_design_identity = new_identity, accept_dataset = 6L)
    saved_other <- brohn_get_entity(store, "dataset", ui_other$id)
    queued <- Filter(function(j) j$status == "queued", brohn_list_jobs(store))
    check("confirmed current study resolves and saves its exact revision instead of floating current", is.null(state$error) && saved_other$body$study_revision == edited_study$revision &&
      length(queued) == 1L && queued[[1L]]$request$study_revision == edited_study$revision && queued[[1L]]$request$study_hash == brohn_hash(edited_study$body))
    brohn_cancel_job(store, queued[[1L]]$id)
    check("UI-only checks launch no workers or reports", !length(brohn_list_entities(store, "report")) &&
      all(vapply(brohn_list_jobs(store), function(j) j$status == "cancelled" && j$attempt == 0L, logical(1))))
  })
  if ("--mapping-only" %in% commandArgs(trailingOnly = TRUE)) {
    cat("Brohn MaxDiff platform import mapping-only: ", checks, " checks passed; no scientific workers launched.\n", sep = "")
    return(invisible(NULL))
  }

  accepted <- brohn_curate_dataset(store, ingested$id, metadata, ingested$revision, study$id, study$revision)
  queued <- brohn_queue_dataset(store, accepted$id)
  check("identical pinned dataset requests deduplicate", queued$id == brohn_queue_dataset(store, accepted$id)$id)
  run_job <- function(job, succeeds = TRUE) {
    force(job)
    claim <- brohn_claim_job(store, "maxdiff-import-platform-qa", lease_seconds = 90)
    stopifnot(!is.null(claim), claim$id == job$id)
    brohn_process_job(store, claim, timeout_seconds = 90)
    done <- brohn_get_job(store, job$id)
    if (succeeds && done$status != "succeeded") stop("Actual MaxDiff worker failed: ", brohn_json(done$error), call. = FALSE)
    done
  }
  # Change both mutable heads after queueing. The task must still use the old
  # exact CSV mapping revision and exercise wording from its original design.
  current_study <- brohn_study(store, study$id)
  amended <- current_study$body; amended$maxdiff[[1L]]$settings$prompt <- "Later changed question wording"
  amended_study <- brohn_save_study(store, amended, current_study$revision)
  revised_metadata <- metadata; revised_metadata$origin_statement <- "Later source note amendment; original synthetic evidence unchanged."
  later_dataset <- brohn_curate_dataset(store, accepted$id, revised_metadata, accepted$revision, study$id, study$revision)
  done <- run_job(queued)
  report <- brohn_get_entity(store, "report", done$result$report_id)
  a <- report$body$analysis; result <- a$choice_tasks[[1L]]
  check("actual R child publishes a complete saved explicit-choice result", done$status == "succeeded" && a$kind == "explicit_choice" &&
    result$schema == "brohn-maxdiff-result/1.0" && report$body$origin == "sample")
  check("worker matches independent balanced six-pair likelihood and utility oracle", result$model$status == "estimated" &&
    near(result$model$diagnostics$negative_log_likelihood, 6*log(6)) && all(abs(vapply(result$model$utilities, `[[`, numeric(1), "utility")) < 1e-9))
  check("complete-pair scores use actual eligible exposures", all(vapply(result$items, function(item)
    item$best_count == 2L && item$worst_count == 2L && item$answered_exposures == 6L && item$missing_exposures == 1L && item$exposure_adjusted_score == 0, logical(1))))
  check("report retains partial, unpresented and excluded-other-exercise evidence", a$quality$source_row_count == 9L && a$quality$selected_row_count == 8L &&
    a$quality$excluded_row_count == 1L && a$quality$complete_pairs == 6L && a$quality$missing_pairs == 1L && a$quality$unpresented_exposures == 1L &&
    a$observations[[7L]]$best_id == "item-1" && is.null(a$observations[[7L]]$worst_id) && !a$source_rows[[9L]]$selected)
  check("one declared person and session do not become independent row participants", a$quality$participant_count == 1L && a$quality$session_count == 1L && result$quality$repeated_set_exposures == 6L)
  check("source row identity and exact offered orders survive the supervised boundary", a$source_rows_hash == brohn_hash(a$source_rows) &&
    all(vapply(seq_along(rows), function(i) identical(rows[[i]]$item_order, a$observations[[i]]$item_order), logical(1))))
  check("queued report pins both earlier mapping and study despite mutable-head changes", report$body$provenance$dataset_revision == accepted$revision &&
    report$body$provenance$dataset_hash == brohn_hash(accepted$body) && report$body$provenance$study_revision == study$revision &&
    report$body$provenance$design_hash == brohn_hash(design) && report$body$provenance$design$maxdiff[[1L]]$settings$prompt == exercise$settings$prompt &&
    brohn_get_entity(store, "dataset", accepted$id)$revision == later_dataset$revision && brohn_study(store, study$id)$revision == amended_study$revision)
  check("canonical scorer source points to the exact immutable CSV and mapping revision", result$source$hash == source_hash && result$source$id == ingested$id &&
    result$source$revision == accepted$revision && result$source$origin == "sample")
  check("import does not manufacture response time, implicit scoring or physiology output", is.null(a$implicit_tasks) && is.null(a$series) &&
    all(vapply(a$observations, function(row) is.null(row$response_time_ms) && is.null(row$latency_ms), logical(1))))
  identities <- report$body$processing$code_hashes
  check("actual source closure pins MaxDiff core, import and child bootstrap", all(c("R/platform-maxdiff.R", "R/platform-maxdiff-import.R", "R/platform-jobs.R", "scripts/analysis-worker.R") %in% names(identities)) &&
    all(vapply(names(identities), function(path) identical(identities[[path]], digest::digest(file = path, algo = "sha256")), logical(1))))
  check("published result receipt references verified immutable bytes", report$body$result_object$hash == done$result$output_hash &&
    digest::digest(file = brohn_object_path(store, report$body$result_object$hash), algo = "sha256") == done$result$output_hash)
  retained <- brohn_read_json_file(brohn_object_path(store, report$body$result_object$hash))
  # Scientific arithmetic uses independent numeric tolerances above. Storage
  # serialization must preserve exact binary64 values and canonical hashes.
  check("full canonical result object retains all source-row evidence", brohn_hash(retained$report$analysis) == brohn_hash(a) &&
    isTRUE(all.equal(retained$report$analysis, a, tolerance = 0)) &&
    brohn_hash(retained$report$analysis$source_rows) == brohn_hash(a$source_rows) &&
    brohn_hash(retained$report$analysis$observations) == brohn_hash(a$observations) && length(retained$report$analysis$source_rows) == 9L)
  source_copy <- file.path(root, "downloaded-original.csv"); brohn_copy_object_download(store, source_hash, source_copy)
  observation_csv <- file.path(root, "downloaded-observations.csv"); brohn_export_report_csv(report$body, observation_csv)
  export_csv <- file.path(root, "downloaded-best-worst-choices.csv")
  brohn_export_report_csv(list(analysis = list(observations = brohn_maxdiff_export_rows(report$body$analysis$choice_tasks))), export_csv)
  export_json <- file.path(root, "downloaded-report.json"); brohn_write_json_file(report$body, export_json)
  export_html <- file.path(root, "downloaded-report.html"); brohn_export_report_html(report$body, export_html, store)
  exported <- brohn_read_table(export_csv, "csv", 20000L)
  reimport <- brohn_import_maxdiff_analysis(exported, metadata, design,
    list(hash = digest::digest(file = export_csv, algo = "sha256"), origin = "sample", id = "original-analysis-export", revision = 1L))
  check("full original download retains excluded exercise bytes and is writeable", digest::digest(file = source_copy, algo = "sha256") == source_hash &&
    file.access(source_copy, 2L) == 0L && nrow(brohn_read_table(source_copy, "csv", 20000L)) == 9L)
  check("actual report CSV exports all selected exposures and reproduces the likelihood", nrow(exported) == 8L &&
    nrow(brohn_read_table(observation_csv, "csv", 20000L)) == 8L && near(reimport$choice_tasks[[1L]]$model$diagnostics$negative_log_likelihood, 6*log(6)))
  check("JSON and offline HTML retain useful source-bound results", brohn_hash(brohn_read_json_file(export_json)) == brohn_hash(report$body) &&
    isTRUE(all.equal(brohn_read_json_file(export_json), report$body, tolerance = 0)) &&
    brohn_read_json_file(export_json)$analysis$source_rows_hash == a$source_rows_hash &&
    grepl("<html", paste(readLines(export_html, warn = FALSE), collapse = "\n"), fixed = TRUE) && file.info(export_html)$size > 1000L)
  report_hash <- brohn_hash(report$body)
  second <- run_job(brohn_queue_dataset(store, accepted$id, accepted$revision, force = TRUE))
  again <- brohn_get_entity(store, "report", second$result$report_id)
  check("explicit reanalysis produces a separate report with the same pinned analysis", second$id != done$id && again$id != report$id &&
    brohn_hash(again$body$analysis) == brohn_hash(a))
  check("prior report remains unchanged and has one immutable revision", brohn_hash(brohn_get_entity(store, "report", report$id)$body) == report_hash &&
    length(brohn_entity_history(store, "report", report$id)) == 1L)

  # These are real rejected jobs, not synthetic displayed scores. Original
  # immutable objects are never edited to create corruption fixtures.
  before <- length(brohn_list_entities(store, "report"))
  wrong_design <- brohn_ingest_dataset(store, csv, "Original response hash conflict", modality = "maxdiff", origin = "sample")
  wrong_design <- brohn_curate_dataset(store, wrong_design$id, metadata, wrong_design$revision, study$id, amended_study$revision)
  rejected <- run_job(brohn_queue_dataset(store, wrong_design$id), succeeds = FALSE)
  check("changed exercise framing fails actual worker rather than scoring another question", rejected$status == "failed" &&
    grepl("design hash", brohn_json(rejected$error), fixed = TRUE) && length(brohn_list_entities(store, "report")) == before)
  mixed_path <- file.path(root, "original-row-origin-conflict.csv")
  mixed <- table; mixed$origin[[1L]] <- "live"
  utils::write.table(mixed, mixed_path, sep = ",", row.names = FALSE, quote = TRUE, qmethod = "double", na = "", fileEncoding = "UTF-8")
  mixed_dataset <- brohn_ingest_dataset(store, mixed_path, "Original origin conflict fixture", modality = "maxdiff", origin = "sample")
  mixed_dataset <- brohn_curate_dataset(store, mixed_dataset$id, metadata, mixed_dataset$revision, study$id, study$revision)
  rejected <- run_job(brohn_queue_dataset(store, mixed_dataset$id), succeeds = FALSE)
  check("selected row origin conflict fails the actual child without a report", rejected$status == "failed" &&
    grepl("origin", brohn_json(rejected$error), fixed = TRUE) && length(brohn_list_entities(store, "report")) == before)
  tampered <- queued$request; tampered$study_hash <- strrep("f", 64L)
  rejected <- run_job(brohn_enqueue_job(store, "analyse_dataset", tampered, "original-maxdiff-request-hash-rejection"), succeeds = FALSE)
  check("tampered frozen design request is rejected before publication", rejected$status == "failed" && length(brohn_list_entities(store, "report")) == before)
  scratch <- file.path(root, "direct-integrity-attempt"); dir.create(scratch)
  input <- brohn_job_input(store, queued); input$source_path <- mixed_path
  check("source path with different bytes fails strict input hashing", rejects(brohn_analyse_input(input, scratch)))
  check("failed jobs never alter the original saved dataset or source bytes", digest::digest(file = brohn_object_path(store, source_hash), algo = "sha256") == source_hash &&
    brohn_hash(brohn_get_entity(store, "report", report$id)$body) == report_hash)
  brohn_close_store(store); store <- brohn_open_store(file.path(root, "workspace"))
  check("new database connection reopens exact immutable report and full result object", brohn_hash(brohn_get_entity(store, "report", report$id)$body) == report_hash &&
    brohn_read_json_file(brohn_object_path(store, done$result$output_hash))$report$analysis$source_rows_hash == a$source_rows_hash)
  cat("Brohn MaxDiff platform import: ", checks, " checks passed (production Shiny handlers and actual supervised R jobs).\n", sep = "")
})
