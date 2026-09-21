# Whole source -> mapping -> frozen R subprocess -> durable report and backup.
source("R/platform-load.R"); brohn_load(ui = FALSE)
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("Gaze job: ", name); checks <<- checks + 1L}
  root <- .brohn_port_temp(); store <- brohn_open_store(file.path(root, "workspace"))
  on.exit({brohn_close_store(store); .brohn_port_cleanup(root)}, add = TRUE)
  brohn_initialise_library(store)
  design <- brohn_new_design("Raw gaze job", id = "study-gaze-job")
  design$stimuli[[1]]$aois <- list(list(id = "left", label = "Label", x = 0, y = 0, width = .5, height = 1))
  saved <- brohn_put_entity(store, "study", design$id, design)
  data <- data.frame(time = seq(0, 410, 10), x = c(rep(.25, 21), rep(.75, 21)), y = .5, valid = TRUE,
    person = "p1", session = "s1", stimulus = "stimulus-a", exposure = "e1", onset = 0, offset = 410)
  source_path <- file.path(root, "samples.csv"); utils::write.csv(data, source_path, row.names = FALSE)
  m <- list(gaze_representation = "samples", unit = "stimulus_normalized", time_unit = "ms", time_column = "time",
    x_column = "x", y_column = "y", valid_column = "valid", participant_column = "person", session_column = "session",
    stimulus_column = "stimulus", exposure_column = "exposure", source_phase = "passive_viewing_only",
    exposure_start_column = "onset", exposure_end_column = "offset", origin_statement = "Original synthetic test samples, not collected research.",
    geometry = list(width_mm = 400, height_mm = 300, distance_mm = 600, center_x_mm = 0, center_y_mm = 0),
    geometry_source = "Declared synthetic 400 by 300 mm plane at 600 mm.",
    parameters = list(velocity_threshold_deg_s = 30, min_fixation_ms = 60, min_saccade_ms = 10, max_gap_ms = 20, threshold_source = "Fixture policy only."))
  dataset <- brohn_ingest_dataset(store, source_path, "Sample source", "gaze", design$id, origin = "sample")
  accepted <- brohn_curate_dataset(store, dataset$id, m, dataset$revision)
  queued <- brohn_queue_dataset(store, dataset$id)
  changed <- design; changed$stimuli[[1]]$aois[[1]]$width <- .8
  invisible(brohn_save_study(store, changed, saved$revision))
  job <- brohn_claim_job(store, "gaze-qa", 60); brohn_process_job(store, job, timeout_seconds = 60)
  complete <- brohn_get_job(store, queued$id)
  check(paste("sampled gaze worker completes", brohn_json(complete$error)), complete$status == "succeeded")
  report <- brohn_get_entity(store, "report", complete$result$report_id)$body
  aoi <- report$analysis$observations[[1]]
  check("selected sampled recipe executes", identical(report$analysis$parameters$method, "brohn-adjacent-ray-ivt/0.1.0-draft"))
  check("original AOI geometry is pinned", report$provenance$design$stimuli[[1]]$aois[[1]]$width == .5 && abs(aoi$valid_share_percent - 100*200/410) < 1e-8)
  check("fixations remain candidate evidence", identical(report$analysis$quality$qualified, FALSE))
  check("source hash remains exact", identical(digest::digest(file = brohn_object_path(store, dataset$body$source$hash), algo = "sha256"), dataset$body$source$hash))
  scratch <- file.path(store$root, "scratch")
  # Native publication intentionally retains bounded receipts/control logs.
  # Scientific job scratch and temporary bulk copies must still be removed.
  publication_files <- list.files(file.path(scratch, "publication"), recursive = TRUE, full.names = TRUE)
  check("immutable output stored after scientific scratch and bulk copies removed", file.exists(brohn_object_path(store, report$result_object$hash)) &&
    !length(setdiff(list.files(scratch), "publication")) &&
    all(basename(publication_files) %in% c("request.json", "receipt.json", "status.json", "stdout.txt", "stderr.txt")) &&
    all(file.info(publication_files)$size <= 4*1024^2))
  destination <- file.path(root, "backup")
  backup_job <- brohn_enqueue_job(store, "backup_workspace", list(destination = destination), "gaze-qa-backup")
  brohn_process_job(store, brohn_claim_job(store, "backup-qa", 60), timeout_seconds = 60)
  completed <- brohn_get_job(store, backup_job$id)
  check(paste("backup child completes", brohn_json(completed$error)), completed$status == "succeeded")
  check("backup has independent integrity verification", isTRUE(brohn_verify_backup(destination)$verified))
  check("backup is recorded in the catalog", !is.null(brohn_get_entity(store, "backup", completed$result$backup_id)))
  cat(sprintf("PASS: %d raw gaze / backup subprocess integration assertions\n", checks))
})
