# Local, single-user prepared-data flow; acquisition remains separate.
copy_draft_for_import <- function(bundle) {
  record_assert(draft_editable(bundle), "Only an empty draft can be copied for import.")
  copy <- create_draft("preview")
  id <- copy$study$id
  copy$study <- bundle$study
  copy$study$id <- id
  copy$study$title <- paste0(sub(" \\x{00b7} sample$", "", draft_title(bundle), perl = TRUE), " - working copy")
  copy$study$revision <- 1L
  copy$session$study_id <- id
  copy$session$study_revision <- 1L
  record_assert(!length(validate_bundle(copy)), "Could not create a valid working copy.")
  copy
}

save_draft_analysis <- function(report, draft_path) {
  directory <- paste0(draft_path, ".analyses")
  if (!dir.exists(directory)) record_assert(dir.create(directory), "Could not create the analysis folder.")
  path <- tempfile(paste0("r", sprintf("%.0f", report$study$revision), "-"), tmpdir = directory, fileext = ".json")
  save_prepared_report(report, path)
  path
}

open_draft_analysis <- function(bundle, draft_path) {
  if (is.null(draft_path)) return(NULL)
  directory <- paste0(draft_path, ".analyses")
  if (!dir.exists(directory)) return(NULL)
  prefix <- paste0("^r", sprintf("%.0f", bundle$study$revision), "-.*\\.json$")
  paths <- list.files(directory, pattern = prefix, full.names = TRUE)
  if (!length(paths)) return(NULL)
  path <- paths[order(file.info(paths)$mtime, decreasing = TRUE)][[1]]
  report <- read_prepared_report(path, local_limits = TRUE)
  record_assert(isTRUE(all.equal(report$study, bundle$study)), "The saved analysis belongs to a different study snapshot. Import the prepared CSV again.")
  list(report = report, path = path)
}

prepared_import_ui <- function(bundle) {
  if (bundle$session$mode == "sample") return(shiny::div(class = "panel",
    shiny::h2("Use this design with your prepared data."),
    shiny::p("Create a working copy with these images, areas and questions. Imported data will have a separate origin from the fictional sample."),
    shiny::actionButton("copy_for_import", "Create a working copy", class = "btn-primary")))
  if (!draft_editable(bundle)) return(NULL)
  shiny::div(class = "panel", shiny::span(class = "eyebrow", "PREPARED DATA IMPORT"),
    shiny::h2("Bring prepared gaze data into this study."),
    shiny::p("Choose a CSV of prepared viewing intervals. The app checks it, calculates the areas and saves a reproducible report automatically."),
    shiny::div(class = "info-note", "This early importer needs prepared intervals in milliseconds and normalized image coordinates. It does not convert an eye tracker's raw export or verify calibration. The analysis method remains a draft."),
    if (length(bundle$study$stimulus_assets) != 2 || !length(bundle$study$aois))
      shiny::p("First add both study images and define areas in Plan. Use matching area names on both designs for a paired comparison.") else
        shiny::fileInput("gaze_csv", "Prepared gaze CSV", accept = c(".csv", "text/csv"),
          buttonLabel = "Choose CSV", placeholder = "Up to 1 MiB and 20,000 intervals"),
    shiny::tags$details(shiny::tags$summary("Required columns and preparation"),
      shiny::p(shiny::tags$code("participant_id, stimulus_id, start_ms, end_ms, x, y, valid, phase")),
      shiny::p(paste("Stimulus IDs for this study:", paste(bundle$study$stimulus_ids, collapse = ", "))),
      shiny::p("Use UTF-8 CSV, decimal numbers and true/false validity. Phase is passive_viewing or active_response. Invalid coordinates may be blank. Keep one prepared exposure timeline per participant and stimulus; repeated exposures are not supported yet."),
      shiny::downloadButton("export_gaze_template", "Download column template", icon = NULL, class = "btn-outline-secondary")),
    shiny::p(class = "muted", "Local limits: 1 MiB, 20,000 intervals, 500 participants and 40 areas. The report stays on this computer with its study revision and original CSV bytes. Changing the draft clears the current result; earlier saved reports are retained."))
}
