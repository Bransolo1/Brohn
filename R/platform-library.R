# Study, dataset and design libraries over the versioned workspace catalog.
brohn_workspace_path <- function() {
  configured <- Sys.getenv("BROHN_WORKSPACE")
  if (nzchar(configured)) return(configured)
  base <- if (.Platform$OS.type == "windows") Sys.getenv("LOCALAPPDATA") else Sys.getenv("XDG_DATA_HOME")
  if (!nzchar(base)) base <- file.path(path.expand("~"), ".local", "share")
  file.path(base, "Brohn", "workspaces", "default")
}
brohn_initialise_library <- function(store) {
  brohn_store_batch(store, function() {
    if (is.null(brohn_get_entity(store, "project", "default")))
      brohn_put_entity(store, "project", "default", list(id = "default", title = "My research", description = "", archived = FALSE))
  })
  invisible(store)
}
brohn_project <- function(store, id = "default") {
  record <- brohn_get_entity(store, "project", id)
  brohn_require(!is.null(record) && !isTRUE(record$body$archived), "Choose an available project.")
  record
}
brohn_create_study <- function(store, title, template = "comparison", project_id = "default") {
  brohn_project(store, project_id)
  design <- brohn_new_design(title, template, project_id = project_id)
  brohn_validate_design(design)
  brohn_put_entity(store, "study", design$id, design, project_id = project_id)
}
brohn_study <- function(store, id, revision = NULL) {
  result <- brohn_get_entity(store, "study", id, revision)
  brohn_require(!is.null(result), "This study could not be found.")
  brohn_validate_design(result$body)
  result
}
brohn_save_study <- function(store, design, expected_revision) {
  brohn_validate_design(design); brohn_project(store, design$project_id)
  current <- brohn_study(store, design$id)
  brohn_require(!isTRUE(current$body$archived), "Restore this study before editing its design.")
  brohn_require(identical(current$project_id, design$project_id), "Moving a study between projects requires an explicit move operation.")
  brohn_put_entity(store, "study", design$id, design, expected_revision, design$project_id)
}
brohn_studies <- function(store, project_id = NULL, query = "", archived = FALSE, limit = 500) {
  limit <- .brohn_store_integer(limit, "Result limit", 1L, 10000L)
  read <- function() {
    records <- list(); offset <- 0L
    repeat {
      page <- brohn_search_library(store, "study", query, project_id, archived, limit = min(100L, limit-length(records)), offset = offset)
      records <- c(records, page$records)
      if (!page$has_next || length(records) >= limit) break
      offset <- offset + length(page$records)
    }
    records
  }
  if (RSQLite::sqliteIsTransacting(store$con)) read() else DBI::dbWithTransaction(store$con, read())
}
brohn_study_choices <- function(store, project_id) {
  .brohn_store_ready(store); brohn_require(brohn_valid_id(project_id), "Choose a project for study links.")
  # Labels only: scientific bodies stay on disk. The server-side selectize
  # endpoint searches this metadata across all available study identities.
  rows <- DBI::dbGetQuery(store$con, paste("SELECT e.id,json_extract(v.body_json,'$.title') AS title,",
    "coalesce(json_extract(v.body_json,'$.archived'),0) AS archived FROM entities e JOIN entity_versions v",
    "ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision WHERE e.kind='study' AND e.project_id=?",
    "ORDER BY e.updated_at DESC,e.id ASC"), params = list(project_id))
  labels <- if (nrow(rows)) paste0(rows$title, ifelse(rows$archived != 0, " (archived)", ""), " \u00b7 ", substr(rows$id, pmax(1,nchar(rows$id)-5L), nchar(rows$id))) else character()
  c("No study link" = "", stats::setNames(rows$id, labels))
}
brohn_archive_study <- function(store, id, archived = TRUE, expected_revision = NULL) {
  brohn_require(is.logical(archived) && length(archived) == 1L && !is.na(archived), "Archive choice must be true or false.")
  brohn_store_batch(store, function() {
    record <- brohn_study(store, id)
    if (!is.null(expected_revision)) brohn_require(identical(record$revision, as.integer(expected_revision)), "This study changed. Reload before archiving.")
    if (isTRUE(archived) && exists("brohn_deployments", mode = "function")) {
      deployments <- brohn_deployments(store, id)
      brohn_require(!any(vapply(deployments, function(d) d$status %in% c("open", "paused"), logical(1))), "Close recruitment before archiving this study. Existing data will be preserved.")
    }
    record$body$archived <- archived
    brohn_validate_design(record$body)
    brohn_put_entity(store, "study", record$id, record$body, record$revision, record$project_id)
  })
}
brohn_clone_study <- function(store, id, title = NULL, revision = NULL, project_id = "default") {
  source <- brohn_study(store, id, revision); brohn_project(store, project_id)
  design <- brohn_clone_design(source$body, brohn_default(title, paste(source$body$title, "copy")), project_id)
  design$lineage$source_revision <- source$revision
  brohn_put_entity(store, "study", design$id, design, project_id = project_id)
}
brohn_save_template <- function(store, study_id, title = NULL, revision = NULL) {
  source <- brohn_study(store, study_id, revision)
  id <- brohn_id("template")
  body <- list(schema_version = "brohn-template/1.0.0", id = id,
    title = brohn_default(title, source$body$title), design = source$body,
    source_revision = source$revision, source_hash = brohn_hash(source$body))
  brohn_require(brohn_text(body$title, 240), "Give this template a short name.")
  brohn_put_entity(store, "template", id, body, project_id = source$project_id)
}
brohn_use_template <- function(store, template_id, title = NULL, project_id = "default") {
  template <- brohn_get_entity(store, "template", template_id)
  brohn_require(!is.null(template), "This template is unavailable."); brohn_project(store, project_id)
  design <- brohn_clone_design(template$body$design, brohn_default(title, template$body$title), project_id)
  design$lineage <- list(operation = "use_template", template_id = template_id,
    template_revision = template$revision, design_hash = template$body$source_hash)
  brohn_put_entity(store, "study", design$id, design, project_id = project_id)
}
brohn_attach_png <- function(store, design, stimulus_id, path, filename = basename(path)) {
  brohn_validate_design(design)
  index <- match(stimulus_id, brohn_ids(design$stimuli)); brohn_require(!is.na(index), "Choose an existing stimulus.")
  source <- new_png_asset(path, stimulus_id)
  bytes <- jsonlite::base64_dec(source$data_base64)
  asset <- brohn_store_object(store, bytes = bytes, media_type = "image/png")
  asset$filename <- basename(filename)
  # Read the header directly so the new contract is independent of legacy naming.
  dimensions <- stimulus_png_header(bytes)
  asset$width <- unname(dimensions[["width"]]); asset$height <- unname(dimensions[["height"]])
  previous <- design$stimuli[[index]]$asset
  design$stimuli[[index]]$asset <- asset; design$stimuli[[index]]$type <- "image"
  if (is.null(previous) || !identical(previous$hash, asset$hash)) design$stimuli[[index]]$aois <- list()
  brohn_validate_design(design); design
}
brohn_asset_data_uri <- function(store, asset) {
  if (is.null(asset)) return(NULL)
  brohn_require(asset$media_type %in% c("image/png", "image/jpeg") && asset$size <= 5 * 1024^2, "This asset requires the media player rather than inline preview.")
  path <- brohn_object_path(store, asset$hash)
  bytes <- readBin(path, "raw", n = asset$size + 1)
  brohn_require(length(bytes) == asset$size, "The stored media size changed.")
  paste0("data:", asset$media_type, ";base64,", gsub("[\r\n]", "", jsonlite::base64_enc(bytes)))
}
brohn_copy_object_download <- function(store, hash, destination) {
  source <- brohn_object_path(store, hash)
  brohn_require(!identical(tolower(normalizePath(destination, winslash = "/", mustWork = FALSE)), tolower(source)), "The download destination must be separate from the immutable source.")
  # Objects are read-only. A Shiny/httpuv transfer copy must be writable on
  # Windows so the HTTP server can open it with delete-on-close semantics.
  brohn_require(file.copy(source, destination, overwrite = TRUE, copy.mode = FALSE), "Could not prepare the saved artifact for download.")
  Sys.chmod(destination, "0600")
  brohn_require(identical(digest::digest(file = destination, algo = "sha256"), hash), "The download copy failed its integrity check.")
  invisible(destination)
}
brohn_sample_study <- function(store, title = "Packaging comparison - practice") {
  brohn_store_batch(store, function() {
  record <- brohn_create_study(store, title)
  design <- record$body
  for (i in 1:2) {
    path <- file.path("examples", "stimuli", paste0("sample-design-", letters[i], ".png"))
    design <- brohn_attach_png(store, design, design$stimuli[[i]]$id, path)
    design$stimuli[[i]]$aois <- list(list(id = paste0("aoi-label-", letters[i]), label = "Product label",
      x = .2, y = .25, width = .6, height = .5, asset_hash = design$stimuli[[i]]$asset$hash, source = "sample_design"))
  }
  design$description <- "Original fictional packaging for learning the workflow. No participant observations are included."
  design$instructions <- "View each fictional packaging design, then rate your liking. This is a practice study."
  design$lineage <- list(operation = "original_sample_design", origin = "sample")
    brohn_save_study(store, design, record$revision)
  })
}

brohn_dataset_formats <- function() c(csv = "text/csv", tsv = "text/tab-separated-values",
  edf = "application/x-edf", bdf = "application/x-bdf", fif = "application/x-fif",
  set = "application/x-eeglab", xdf = "application/x-xdf", snirf = "application/x-snirf",
  wav = "audio/wav", mp4 = "video/mp4", webm = "video/webm", mov = "video/quicktime", mkv = "video/x-matroska", avi = "video/x-msvideo", json = "application/json")
brohn_ingest_dataset <- function(store, path, title, modality = "gaze", study_id = NULL,
                                 metadata = list(), project_id = "default", origin = "imported") {
  brohn_project(store, project_id)
  brohn_require(brohn_text(title, 240) && file.exists(path) && !dir.exists(path), "Choose a source file and dataset name.")
  formats <- brohn_dataset_formats(); ext <- tolower(tools::file_ext(path))
  brohn_require(ext %in% names(formats), "This file format has no registered import route.")
  size <- file.info(path)$size
  brohn_require(is.finite(size) && size > 0 && size <= 512 * 1024^2, "Source file must contain data and fit the 512 MiB import limit.")
  brohn_require(modality %in% c("gaze", "prepared_gaze", "eda", "eeg", "ecg", "ppg", "respiration", "emg", "eog", "fnirs", "temperature", "movement", "audio", "video", "implicit", "questionnaire", "maxdiff", "multimodal"), "Select a supported data family.")
  brohn_require(origin %in% c("imported", "sample", "pilot", "live"), "Declare the recording origin.")
  if (!is.null(study_id)) {
    study <- brohn_study(store, study_id)
    brohn_require(identical(study$project_id, project_id), "Attach data only within its authorized project.")
  }
  .brohn_store_json(metadata)
  brohn_store_batch(store, function() {
    object <- brohn_store_object(store, path = path, media_type = unname(formats[[ext]]))
    brohn_require(object$size > 0 && object$size <= 512 * 1024^2, "Source changed or exceeds the import size limit.")
    preview <- list(); columns <- list()
    if (ext %in% c("csv", "tsv")) {
      # Curate the exact captured source, not a mutable upload path read before
      # or after the object copy. A preview failure rolls back its catalog row.
      source_path <- brohn_object_path(store, object$hash)
      table <- utils::read.table(source_path, header = TRUE, sep = if (ext == "csv") "," else "\t",
        nrows = 20, colClasses = "character", check.names = FALSE, comment.char = "", quote = "\"", fileEncoding = "UTF-8", na.strings = character())
      brohn_require(ncol(table) > 0 && ncol(table) <= 1024 && !anyDuplicated(names(table)) && all(nzchar(names(table))), "Data columns must have unique nonempty names.")
      columns <- as.list(names(table))
      preview <- lapply(seq_len(nrow(table)), function(i) as.list(table[i, , drop = FALSE]))
    }
    id <- brohn_id("dataset")
    body <- list(schema_version = "brohn-dataset/1.0.0", id = id, title = title,
      modality = modality, origin = origin, study_id = study_id,
      source = c(object, list(filename = basename(path), format = ext)),
      columns = columns, preview = preview, metadata = metadata, status = "needs_mapping",
      data_revision = 1L, notes = "", source_provenance = list(imported_at = brohn_now(), source_hash = object$hash))
    brohn_put_entity(store, "dataset", id, body, project_id = project_id)
  })
}
brohn_report_for_review <- function(store,id,revision=NULL) {
  record <- brohn_get_entity(store,"report",id,revision)
  brohn_require(!is.null(record),"This saved report is unavailable.")
  brohn_signal_audio_lineage(store,record,verify=FALSE)
  record
}
brohn_curate_dataset <- function(store, id, metadata, expected_revision, study_id = NULL, study_revision = NULL) {
  record <- brohn_get_entity(store, "dataset", id)
  brohn_require(!is.null(record), "This dataset is unavailable.")
  brohn_require(is.list(metadata), "Dataset mapping must be a structured record.")
  if (!missing(study_id)) {
    if (is.null(study_id)) {record$body["study_id"] <- list(NULL); record$body["study_revision"] <- list(NULL)} else {
    study <- brohn_study(store, study_id)
    brohn_require(identical(study$project_id, record$project_id), "This study belongs to a different project.")
    record$body$study_id <- study_id
    if (missing(study_revision)) record$body["study_revision"] <- list(NULL)
    }
  }
  if (!missing(study_revision)) {
    if (!is.null(study_revision)) {
      brohn_require(!is.null(record$body$study_id) && brohn_number(study_revision, 1, .Machine$integer.max, TRUE), "Choose a saved design revision for this recording.")
      brohn_study(store, record$body$study_id, study_revision)
    }
    record$body["study_revision"] <- list(study_revision)
  }
  record$body$metadata <- metadata; record$body$status <- "accepted"; record$body$data_revision <- record$revision + 1L
  if (exists("brohn_validate_dataset_mapping", mode = "function")) brohn_validate_dataset_mapping(record$body)
  else brohn_stop("The data mapping validator must be available before accepting data.")
  if (identical(record$body$modality,"maxdiff")) brohn_validate_maxdiff_mapping(record$body,brohn_study(store,record$body$study_id,record$body$study_revision)$body)
  if (identical(record$body$modality,"implicit")) brohn_read_task_registry(store,record$body,brohn_study(store,record$body$study_id,record$body$study_revision)$body)
  # Validate the proposed mapping before it becomes a saved revision. A failed
  # analysis queue must not leave extracted audio attached to a different study.
  if (exists("brohn_audio_extraction_lineage",mode="function")) brohn_audio_extraction_lineage(store,record)
  else brohn_require(!identical(record$body$source_provenance$acquisition,"video_audio_extraction") &&
    !startsWith(record$id,"dataset-audio-extraction-"),"Derived-audio source authorization is unavailable.")
  brohn_put_entity(store, "dataset", id, record$body, expected_revision, record$project_id)
}

.brohn_library_legacy_snapshot <- function(path) {
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  bytes <- readBin(connection, "raw", n = draft_size_limit + 1L)
  brohn_require(length(bytes) > 0L && length(bytes) <= draft_size_limit, "Legacy draft is empty or exceeds its size limit.")
  text <- rawToChar(bytes); Encoding(text) <- "UTF-8"
  brohn_require(!is.na(iconv(text, from = "UTF-8", to = "UTF-8")), "Legacy draft must contain UTF-8 JSON.")
  list(bundle = bundle_from_json(text), bytes = bytes,
    hash = digest::digest(bytes, algo = "sha256", serialize = FALSE))
}
brohn_import_legacy <- function(store, directory) {
  if (!is.null(store$hosted_profile)) brohn_hosted_require_action(store, "server_folder_import")
  brohn_require(dir.exists(directory), "The legacy draft folder is unavailable.")
  paths <- list.files(directory, pattern = "\\.json$", full.names = TRUE, recursive = FALSE)
  brohn_require(length(paths) <= 10000, "Legacy folder exceeds the supported migration batch.")
  outcomes <- list()
  for (path in paths) {
    result <- tryCatch(brohn_store_batch(store, function() {
      snapshot <- .brohn_library_legacy_snapshot(path)
      bundle <- snapshot$bundle
      fingerprint <- snapshot$hash
      migration_id <- paste0("legacy-", fingerprint)
      prior <- brohn_get_entity(store, "migration", migration_id)
      if (!is.null(prior)) list(filename = basename(path), status = "already_imported", study_id = prior$body$study_id)
      else {
        design <- brohn_legacy_design(bundle$study)
        for (i in seq_along(design$stimuli)) {
          s <- design$stimuli[[i]]
          old <- Filter(function(a) identical(a$stimulus_id, s$id), brohn_default(bundle$study$stimulus_assets, list()))
          if (length(old)) {
            bytes <- jsonlite::base64_dec(old[[1]]$data_base64); dimensions <- stimulus_png_decode(bytes)
            asset <- brohn_store_object(store, bytes = bytes, media_type = "image/png")
            asset$width <- unname(dimensions[["width"]]); asset$height <- unname(dimensions[["height"]])
            design$stimuli[[i]]$asset <- asset
            old_aois <- brohn_default(bundle$study$aois, list())
            old_aois <- Filter(function(a) identical(a$stimulus_id, s$id), old_aois)
            design$stimuli[[i]]$aois <- lapply(old_aois, function(a) list(id = a$id, label = a$label, x = a$x, y = a$y,
              width = a$width, height = a$height, asset_hash = asset$hash, source = "legacy_design"))
          }
        }
        brohn_validate_design(design)
        history_paths <- c(path,
          list.files(paste0(path, ".analyses"), pattern = "\\.json$", full.names = TRUE),
          list.files(paste0(path, ".protocols"), pattern = "\\.json$", full.names = TRUE))
        artifacts <- lapply(history_paths, function(p) {
          obj <- if (identical(p, path)) brohn_store_object(store, bytes = snapshot$bytes, media_type = "application/json") else
            brohn_store_object(store, path = p, media_type = "application/json")
          list(filename = basename(p), type = if (identical(p, path)) "draft" else if (grepl(".analyses/", gsub("\\\\", "/", p), fixed = TRUE)) "legacy_report" else "legacy_protocol", object = obj)
        })
        saved <- brohn_put_entity(store, "study", design$id, design, project_id = "default")
        record <- list(source_hash = fingerprint, source_name = basename(path), study_id = saved$id,
          artifacts = artifacts, migrated_at = brohn_now(), legacy_origin = bundle$session$mode)
        brohn_put_entity(store, "migration", migration_id, record)
        list(filename = basename(path), status = "imported", study_id = saved$id, preserved_artifacts = length(artifacts))
      }
    }), error = function(e) list(filename = basename(path), status = "failed", reason = conditionMessage(e)))
    outcomes[[length(outcomes)+1L]] <- result
  }
  outcomes
}
