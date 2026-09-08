# Original sample materials and read-only real-service evidence inspection.
args <- commandArgs(trailingOnly = TRUE)
argument <- function(name) {at <- match(name, args); stopifnot(!is.na(at), at < length(args)); args[[at+1L]]}
mode <- args[[1L]]; folder <- normalizePath(argument("--folder"), winslash = "/", mustWork = TRUE)
stopifnot(grepl("^brohn-maxdiff-delivery-", basename(folder)))
if (mode == "serve") {
  # Execute the actual participant launcher. The only fixture addition is a
  # local stop-file watcher that interrupts httpuv's loop, letting its on.exit
  # server/database cleanup run. This service never starts scientific workers.
  stop_file <- file.path(folder, "stop.request")
  stopifnot(!file.exists(stop_file))
  check_stop <- function() {if (file.exists(stop_file)) httpuv::interrupt() else later::later(check_stop, .2)}
  later::later(check_stop, .2)
  source("scripts/run-participant.R", encoding = "UTF-8")
  cat("Original MaxDiff QA participant service stopped gracefully.\n")
} else {
  source("R/platform-load.R"); brohn_load(ui = FALSE)
  store <- brohn_open_store(argument("--root"))
  local({
    on.exit(brohn_close_store(store), add = TRUE)
    config_path <- file.path(folder, "fixture.json")
    if (mode == "prepare_regressions") {
      design <- brohn_new_design("Original camera persistence regression", "survey")
      design$instructions <- "Original fixture: after camera setup, answer the explicit liking question."
      design$questions <- list(brohn_question("Original camera regression liking", "rating", "end", "original-camera-liking"))
      design$camera <- list(schema = "brohn-camera-policy/1.0", required = FALSE, audio = FALSE,
        consent_text = "Original fixture: optional camera recording is described only for cancellation and decline tests.",
        retention_text = "Original synthetic QA only. Declines retain no video; any test evidence stays in this isolated workspace.",
        width = 320L, height = 240L, frame_rate = 15L, max_duration_s = 30L, max_bytes = 8*1024^2, analysis_profile = "none")
      saved <- brohn_put_entity(store, "study", design$id, design)
      optional <- brohn_publish(store, design$id, origin = "sample", quota = 10L, alias_required = TRUE)
      design$camera$required <- TRUE
      brohn_put_entity(store, "study", design$id, design, expected_revision = saved$revision)
      required <- brohn_publish(store, design$id, origin = "sample", quota = 10L, alias_required = TRUE)
      base <- paste0("http://127.0.0.1:", argument("--port"))
      brohn_write_json_file(list(study_id = design$id, title = design$title,
        urls = list(optional = paste0(base, "/participant/?token=", optional$token), required = paste0(base, "/participant/?token=", required$token)),
        fake_video_path = file.path(folder, "original-persistence-camera-320x240.y4m")), file.path(folder, "camera-regression.json"))
    } else if (mode == "prepare") {
      design <- brohn_new_design("Original complete best-worst delivery fixture", "survey")
      design$instructions <- "Original fixture: choose the most and least useful feature in each set, then give an explicit liking answer."
      make_exercise <- function(id, required, count) {
        exercise <- brohn_maxdiff_new(id = id)
        exercise$title <- if (required) "Original required best-worst choices" else "Original optional best-worst choice"
        exercise$items <- list(list(id = "original-convenience", label = "Original convenient feature"),
          list(id = "original-durability", label = "Original durable feature"), list(id = "original-battery", label = "Original battery feature"))
        exercise$sets <- lapply(seq_len(count), function(i) list(id = paste0(id, "-set-", i), item_ids = as.list(brohn_ids(exercise$items))))
        exercise$settings$prompt <- if (required) "Which original feature is most and least useful?" else "Optional: which original feature is most and least useful?"
        exercise$settings$best_label <- "Most useful"; exercise$settings$worst_label <- "Least useful"
        exercise$settings$required <- required; exercise$settings$set_order <- "seeded"; exercise$settings$item_order <- "seeded"
        exercise$settings$design_rationale <- "Original three-item repeated-set transport fixture; not an optimal consumer-research design."
        exercise
      }
      design$maxdiff <- list(make_exercise("original-required", TRUE, 2L), make_exercise("original-optional", FALSE, 1L))
      question <- brohn_question("Original final explicit liking rating", "number", "end", "original-liking")
      design$questions <- list(question)
      brohn_put_entity(store, "study", design$id, design)
      release <- brohn_publish(store, design$id, origin = "sample", quota = 30L, alias_required = FALSE)
      direct <- design; direct$id <- brohn_id("study"); direct$title <- "Original negative API fixture"; direct$instructions <- ""
      brohn_put_entity(store, "study", direct$id, direct)
      api_release <- brohn_publish(store, direct$id, origin = "sample", quota = 30L, alias_required = FALSE)
      brohn_write_json_file(list(study_id = design$id, design_hash = brohn_hash(design), release = release, direct = api_release), config_path)
    } else if (mode == "inspect") {
      config <- brohn_read_json_file(config_path)
      runs <- lapply(brohn_runs(store), function(run) {
        events <- brohn_run_events(store, run$id); replay <- .brohn_delivery_replay(run$protocol, events)
        list(id = run$id, study_id = run$study_id, origin = run$origin, alias_supplied = run$participant_alias_supplied,
          completion = run$completion_status, transfer = run$transfer_status, protocol = run$protocol,
          protocol_hash = brohn_hash(run$protocol), verified_design_hash = brohn_hash(run$protocol$design),
          verified_choice_hashes = lapply(Filter(function(step) step$type == "maxdiff", run$protocol$timeline), function(step)
            list(step_id = step$id, frozen_hash = step$choice$design_hash,
              source_hash = brohn_hash(brohn_find(run$protocol$design$maxdiff, step$choice$exercise_id)))),
          events = events, event_hashes = as.list(vapply(events, brohn_hash, character(1))),
          replay = list(cursor = replay$cursor, completed_step_ids = replay$completed, withdrawn = replay$withdrawn, run_finished = replay$run_finished,
            active_step_id = replay$active$id, ending_outcome = replay$ending_outcome),
          jobs = brohn_list_jobs(store, 100L, list(run_id = run$id)))
      })
      brohn_write_json_file(list(runs = runs, jobs = brohn_list_jobs(store, 100L), source = config), file.path(folder, "inspection.json"))
    } else stop("Unknown MaxDiff fixture mode.")
  })
}
