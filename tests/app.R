# Run with Rscript tests/app.R after installing shiny and bslib.
source("R/study.R")
source("R/comparison.R")
source("R/presentation.R")
source("R/records.R")
source("R/json.R")
source("R/storage.R")
source("R/drafts.R")
source("R/assets.R")
source("R/aois.R")
source("R/aoi-ui.R")
source("R/presentation-ui.R")
source("R/analysis.R")
source("R/sample-analysis.R")
source("R/gaze-import.R")
source("R/import-report.R")
source("R/import-ui.R")
source("R/protocol.R")
source("R/protocol-storage.R")
source("R/app.R", encoding = "UTF-8")
local({
  directory <- tempfile("research-app-tests-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  server_under_test <- research_server
  formals(server_under_test)$store_dir <- directory
  shiny::testServer(server_under_test, {
    session$setInputs(new_study = 1)
    stopifnot(identical(state$bundle$session$mode, "preview"))
    session$setInputs(study_title = "Packaging test", save_draft = 1)
    stopifnot(is.null(state$error), file.exists(state$path))
    stopifnot(identical(read_bundle(state$path)$study$title, "Packaging test"))
    saved_path <- state$path
    image_path <- file.path(directory, "image.png")
    png::writePNG(array(0.5, c(3, 2, 3)), image_path)
    session$setInputs(stimulus_a = data.frame(name = "image.png", size = file.info(image_path)$size,
                                            type = "image/png", datapath = image_path))
    stopifnot(is.null(state$error), length(read_bundle(saved_path)$study$stimulus_assets) == 1)
    session$setInputs(edit_aoi_a = 1)
    session$setInputs(aoi_selection = "", aoi_label = "Logo", aoi_x = 10, aoi_y = 20,
                     aoi_width = 30, aoi_height = 40, save_aoi = 1)
    stopifnot(length(read_bundle(saved_path)$study$aois) == 1)
    region_id <- state$bundle$study$aois[[1]]$id
    session$setInputs(edit_aoi_a = 2)
    session$setInputs(aoi_selection = region_id)
    session$setInputs(aoi_x = 90, aoi_width = 30, save_aoi = 2)
    stopifnot(grepl("bounds", output$aoi_error), read_bundle(saved_path)$study$aois[[1]]$x == 0.1)
    session$setInputs(aoi_x = 10, aoi_width = 30, save_aoi = 3)
    session$setInputs(continue = 1)
    stopifnot(identical(state$stage, "Questions"))
    session$setInputs(include_liking = TRUE, question_prompt = "How appealing is this?", save_draft = 2)
    stopifnot(identical(read_bundle(saved_path)$study$questions[[1]]$prompt, "How appealing is this?"))
    stopifnot(length(read_bundle(saved_path)$study$stimulus_assets) == 1)
    stopifnot(length(read_bundle(saved_path)$study$aois) == 1)
    session$setInputs(home = 1)
    stopifnot(is.null(state$bundle), length(list_drafts(directory)) == 1)
    session$setInputs(saved_file = saved_path, open_saved = 1)
    stopifnot(identical(draft_title(state$bundle), "Packaging test"))
    # A failed validation leaves the saved draft intact and surfaces a message.
    session$setInputs(study_title = "  ", save_draft = 3)
    stopifnot(!is.null(state$error), identical(read_bundle(saved_path)$study$title, "Packaging test"))
    session$setInputs(study_title = "Packaging test", stage_questions = 1)
    session$setInputs(include_liking = FALSE, save_draft = 4)
    stopifnot(is.null(state$error), !length(read_bundle(saved_path)$study$questions))
    # Simulate a second editor. Saving must not overwrite their revision.
    external <- read_bundle(saved_path)
    external <- revise_draft(external, "Other editor", FALSE)
    save_bundle(external, saved_path, overwrite = TRUE)
    session$setInputs(save_draft = 5)
    stopifnot(grepl("changed since", state$error), identical(read_bundle(saved_path)$study$title, "Other editor"))
  })
  shiny::testServer(server_under_test, {
    session$setInputs(open_sample = 1)
    session$setInputs(control_condition = "A", control_rationale = "Current package",
      presentation_order = "counterbalanced_ab_ba", viewing_seconds = 6, stage_results = 1)
    stopifnot(is.null(state$error), state$stage == "Results",
      state$bundle$study$comparison$control_condition == "A",
      state$sample_report$analysis$summary$mean_difference_pp == 20,
      grepl("test minus control", output$workspace$html, fixed = TRUE))
    path <- state$path
    session$setInputs(stage_review = 1)
    stopifnot(grepl("Order AB", output$workspace$html, fixed = TRUE),
      grepl("Order BA", output$workspace$html, fixed = TRUE),
      grepl("for 6 seconds", output$workspace$html, fixed = TRUE))
    session$setInputs(stage_plan = 1)
    session$setInputs(control_condition = "B", control_rationale = "Revised reference",
      presentation_order = "fixed_ba", viewing_seconds = 7, save_draft = 1)
    stopifnot(is.null(state$sample_report), read_bundle(path)$study$comparison$control_condition == "B")
    session$setInputs(stage_results = 2)
    stopifnot(grepl("control minus test", output$workspace$html, fixed = TRUE),
      state$sample_report$analysis$summary$mean_difference_pp == 20)
    session$setInputs(home = 1)
    session$setInputs(saved_file = path, open_saved = 1)
    stopifnot(state$bundle$study$comparison$rationale == "Revised reference",
      state$bundle$study$presentation$order == "fixed_ba", state$bundle$study$presentation$viewing_duration_ms == 7000)
    session$setInputs(viewing_seconds = 0, stage_results = 3)
    stopifnot(!is.null(state$error), state$stage == "Plan", read_bundle(path)$study$presentation$viewing_duration_ms == 7000)
  })
  shiny::testServer(server_under_test, {
    session$setInputs(open_sample = 1)
    original_id <- state$bundle$study$id
    csv <- file.path(directory, "prepared.csv")
    intervals <- sample_gaze_intervals(state$bundle)
    intervals$valid <- tolower(as.character(intervals$valid))
    write.table(intervals, csv, sep = ",", row.names = FALSE, na = "")
    session$setInputs(copy_for_import = 1)
    stopifnot(is.null(state$error), state$stage == "Collect", state$bundle$session$mode == "preview",
      state$bundle$study$id != original_id, !grepl("sample", draft_title(state$bundle), fixed = TRUE))
    draft_path <- state$path
    session$setInputs(gaze_csv = data.frame(name = "prepared.csv", type = "text/csv", size = file.info(csv)$size, datapath = csv))
    stopifnot(is.null(state$error), state$stage == "Results", is.null(state$sample_report),
      state$import_report$origin == "imported_prepared", state$import_report$analysis$summary$mean_difference_pp == 20,
      file.exists(state$import_path), grepl("IMPORTED PREPARED DATA", output$workspace$html, fixed = TRUE))
    analysis_path <- state$import_path
    session$setInputs(home = 1)
    session$setInputs(saved_file = draft_path, open_saved = 1)
    stopifnot(is.null(state$error), !is.null(state$import_report), state$import_report$analysis$summary$mean_difference_pp == 20)
    session$setInputs(study_title = "Updated after import", save_draft = 1)
    stopifnot(is.null(state$import_report), file.exists(analysis_path))
    session$setInputs(stage_results = 1)
    stopifnot(grepl("import prepared intervals", output$workspace$html, fixed = TRUE))
    # The previous result is retained on disk but must never reappear for a changed revision.
    session$setInputs(home = 2)
    session$setInputs(saved_file = draft_path, open_saved = 2)
    stopifnot(is.null(state$import_report))
    session$setInputs(stage_collect = 1)
    bad <- file.path(directory, "broken.csv")
    writeLines("not,a,prepared,CSV", bad)
    session$setInputs(gaze_csv = data.frame(name = "broken.csv", type = "text/csv", size = file.info(bad)$size, datapath = bad))
    stopifnot(!is.null(state$error), state$stage == "Collect", file.exists(analysis_path))
  })
  shiny::testServer(server_under_test, {
    session$setInputs(open_sample = 1, stage_review = 1)
    session$setInputs(save_protocol_snapshot = 1)
    stopifnot(is.null(state$error), !is.null(state$protocol),
      length(state$protocol$registry$trials) == 2, length(state$protocol$registry$epochs) == 4,
      grepl("Export protocol snapshot", output$workspace$html, fixed = TRUE))
    draft_path <- state$path
    protocol_dir <- paste0(draft_path, ".protocols")
    first <- state$protocol$content_sha256
    first_path <- file.path(protocol_dir, paste0(first, ".json"))
    original <- readBin(first_path, "raw", n = draft_size_limit)
    session$setInputs(save_protocol_snapshot = 2)
    stopifnot(length(list.files(protocol_dir, pattern = "\\.json$")) == 1)
    session$setInputs(home = 1)
    session$setInputs(saved_file = draft_path, open_saved = 1)
    stopifnot(is.null(state$error), state$protocol$content_sha256 == first)
    session$setInputs(study_title = "After snapshot", save_draft = 1)
    stopifnot(is.null(state$error), is.null(state$protocol), identical(readBin(first_path, "raw", n = draft_size_limit), original))
    session$setInputs(stage_review = 2, save_protocol_snapshot = 3)
    stopifnot(is.null(state$error), state$protocol$content_sha256 != first,
      length(list.files(protocol_dir, pattern = "\\.json$")) == 2)
  })
})
stopifnot(inherits(research_ui(), "shiny.tag.list"))
cat("PASS: Shiny draft workflow, validation/stale-save recovery, control design and sample result invalidation\n")
