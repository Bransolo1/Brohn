# Reviewed single-stream analogue curation; source clocks and identities remain
# explicit and all original multistream artifacts remain immutable.
brohn_stream_modalities <- function() c("eeg", "eda", "ecg", "ppg", "respiration", "emg")
brohn_stream_units <- function(modality) switch(modality,
  eeg = c("uV", "mV", "V"), ecg = c("uV", "mV", "V"), emg = c("uV", "mV", "V"),
  eda = c("uS", "S"), ppg = c("a.u.", "V", "mV"), respiration = c("a.u.", "V", "mV", "L", "L/s"), character())
brohn_stream_unit <- function(value) gsub("\u00b5|\u03bc", "u", value)

brohn_stream_standard_parameters <- function(modality, sampling_rate) {
  switch(modality,
    eeg = list(recipe = "eeg-welch-channel/1.0", window_s = 2, overlap_fraction = .5,
      bands_hz = list(delta = list(1,4), theta = list(4,8), alpha = list(8,13), beta = list(13,30), gamma = list(30,45)), relative_denominator_hz = list(1,45)),
    eda = list(recipe = "eda-neurokit-highpass/1.0", phasic_cutoff_hz = .05, amplitude_min_relative_prominence = .1, edge_exclusion_s = 10),
    ecg = list(recipe = "ecg-neurokit-detected-rr/1.0", powerline_hz = 50, edge_exclusion_s = 2, interval_min_ms = 300, interval_max_ms = 2000, frequency_min_duration_s = 300),
    ppg = list(recipe = "ppg-elgendi-detected-prv/1.0", edge_exclusion_s = 2, interval_min_ms = 300, interval_max_ms = 2000, frequency_min_duration_s = 300),
    respiration = list(recipe = "respiration-khodadad-cycles/1.0", edge_exclusion_s = 5),
    emg = list(recipe = "emg-butterworth-rms/1.0", highpass_hz = 20, lowpass_hz = min(450, sampling_rate*.4), rms_window_s = .05,
      edge_exclusion_s = .25, burst_threshold_uv = NULL, burst_min_duration_s = .1), NULL)
}

brohn_validate_stream_selection <- function(stream, selection) {
  s <- stream$manifest
  brohn_require(identical(s$schema, "brohn-imported-stream/1.0") && identical(s$kind, "signal"), "Select an analogue signal stream. Event markers and unclassified streams remain preserved source data.")
  brohn_require(stream$origin %in% c("sample", "imported", "pilot", "live"), "Resolve this stream's mixed or unclassified origin before creating analysis inputs.")
  brohn_fields(selection, c("schema", "channel_ids", "modality", "unit", "sampling_rate", "participant_id", "session_id", "origin_statement", "unit_rationale", "confirm_source_units", "confirm_boundaries", "run_analysis"), label = "Stream curation selection")
  brohn_require(identical(selection$schema, "brohn-stream-selection/1.0") && selection$modality %in% brohn_stream_modalities(), "Choose a supported analogue analysis family.")
  brohn_require(brohn_array(selection$channel_ids) && length(selection$channel_ids) >= 1L && length(selection$channel_ids) <= 64L &&
    !anyDuplicated(unlist(selection$channel_ids)) && all(vapply(selection$channel_ids, brohn_valid_id, logical(1))) &&
    all(unlist(selection$channel_ids) %in% brohn_ids(s$channels)), "Select distinct scalar channels from this stream.")
  brohn_require(brohn_number(selection$sampling_rate, 1, 100000) && identical(as.numeric(selection$sampling_rate), as.numeric(s$nominal_srate)),
    "Confirm the source's positive nominal sampling rate. Irregular or absent rates need a separately specified resampling approach.")
  brohn_require(brohn_text(selection$unit, 80) && brohn_stream_unit(selection$unit) %in% brohn_stream_units(selection$modality), "Choose a supported signal unit for this analysis family.")
  brohn_require(brohn_text(selection$origin_statement, 4000) && brohn_text(selection$unit_rationale, 4000), "Describe the source/identity review and the evidence for the selected units, including any missing source-unit declaration.")
  brohn_require(isTRUE(selection$confirm_source_units) && isTRUE(selection$confirm_boundaries), "Confirm the source units and listwise missing-row/boundary policy.")
  brohn_require(is.logical(selection$run_analysis) && length(selection$run_analysis) == 1L && !is.na(selection$run_analysis), "Choose whether to run standard channel analysis after preparation.")
  if (isTRUE(selection$run_analysis)) {
    minimum_rate <- c(eeg = 90, eda = 8, ecg = 100, ppg = 25, respiration = 10, emg = 250)[[selection$modality]]
    brohn_require(selection$sampling_rate >= minimum_rate, paste("The standard", toupper(selection$modality), "recipe needs at least", minimum_rate,
      "Hz. Uncheck automatic analysis to prepare the source for a separately supported recipe."))
  }
  for (name in c("participant_id", "session_id")) brohn_require(is.null(selection[[name]]) ||
    (brohn_text(selection[[name]], 200) && !selection[[name]] %in% c("NA", "N/A", "null", "NaN", "nan")), "Use an explicit participant/session code for missing identities; leave it empty when the source already supplies every identity.")
  for (id in unlist(selection$channel_ids)) {
    channel <- brohn_find(s$channels, id)
    brohn_require(channel$value_type %in% c("float32", "float64", "int8", "int16", "int32", "int64"), "Text and boolean channels cannot become numeric research measurements.")
    for (name in c("scale", "offset")) if (!is.null(channel[[name]])) {
      value <- suppressWarnings(as.numeric(channel[[name]]))
      brohn_require(length(value) == 1L && is.finite(value) && value == if (name == "scale") 1 else 0, "The source declares calibration scaling or offsets. Provide a separately calibrated source before curation.")
    }
    if (brohn_text(channel$unit, 80)) brohn_require(brohn_stream_unit(channel$unit) %in% brohn_stream_units(selection$modality), "A source unit is incompatible with the chosen analysis family; do not relabel uncalibrated values.")
  }
  invisible(selection)
}

brohn_queue_stream_curation <- function(store, stream_id, selection, revision = NULL, force = FALSE) {
  record <- brohn_get_entity(store, "stream", stream_id, revision)
  brohn_require(!is.null(record), "The selected preserved stream is unavailable."); brohn_project(store, record$project_id)
  brohn_validate_stream_selection(record$body, selection)
  imported <- brohn_stream_import(store, record$body$import_id)
  source <- brohn_get_entity(store, "dataset", record$body$source_dataset_id, record$body$source_dataset_revision)
  brohn_require(!is.null(source) && identical(source$body$source$hash, record$body$source_hash) && identical(source$project_id, record$project_id) &&
    record$id %in% unlist(imported$body$stream_ids), "Preserved stream lineage does not match its original dataset/import.")
  canonical <- Filter(function(a) identical(a$kind, "stream_samples_jsonl"), record$body$manifest$artifacts)
  brohn_require(length(canonical) == 1L, "The complete canonical stream artifact is unavailable.")
  brohn_object_path(store, canonical[[1]]$hash)
  request <- list(stream_id = record$id, stream_revision = record$revision, stream_hash = brohn_hash(record$body),
    import_id = imported$id, import_revision = imported$revision, import_hash = brohn_hash(imported$body),
    dataset_id = source$id, dataset_revision = source$revision, dataset_hash = brohn_hash(source$body),
    canonical_hash = canonical[[1]]$hash, source_hash = source$body$source$hash, project_id = record$project_id,
    selection = selection, recipe = "analogue-stream-curation/1.0")
  brohn_enqueue_job(store, "extract_stream", request, paste0("stream-curation:", brohn_hash(request), if (isTRUE(force)) paste0(":", brohn_id("retry")) else ""))
}

brohn_stream_curation_input <- function(store, job) {
  r <- job$request
  record <- brohn_get_entity(store, "stream", r$stream_id, r$stream_revision)
  imported <- brohn_get_entity(store, "stream_import", r$import_id, r$import_revision)
  source <- brohn_get_entity(store, "dataset", r$dataset_id, r$dataset_revision)
  brohn_require(!is.null(record) && !is.null(imported) && !is.null(source) && identical(brohn_hash(record$body), r$stream_hash) &&
    identical(brohn_hash(imported$body), r$import_hash) && identical(brohn_hash(source$body), r$dataset_hash) &&
    identical(record$project_id, r$project_id) && identical(source$project_id, r$project_id) && identical(imported$project_id, r$project_id),
    "Pinned stream, import or raw source revision changed or failed its integrity check.")
  brohn_validate_stream_selection(record$body, r$selection)
  canonical <- Filter(function(a) identical(a$kind, "stream_samples_jsonl"), record$body$manifest$artifacts)
  brohn_require(length(canonical) == 1L && identical(canonical[[1]]$hash, r$canonical_hash) &&
    identical(record$body$source_hash, r$source_hash) && identical(source$body$source$hash, r$source_hash), "Pinned stream objects refer to a different source.")
  lapply(record$body$manifest$artifacts, function(a) brohn_object_path(store, a$hash))
  brohn_object_path(store, r$source_hash)
  list(schema = "brohn-analysis-input/1.0", operation = "extract_stream", stream = record$body, stream_revision = record$revision,
    imported = imported$body, import_revision = imported$revision, dataset = source$body, dataset_revision = source$revision,
    project_id = r$project_id, selection = r$selection, canonical_hash = r$canonical_hash,
    source_path = brohn_object_path(store, r$canonical_hash))
}

brohn_stream_curation_request <- function(input, scratch) {
  directory <- file.path(scratch, "artifacts")
  brohn_require(dir.exists(directory) || dir.create(directory), "Cannot create stream curation artifact directory.")
  list(schema = "brohn-stream-extract-request/1.0", operation = "extract_stream", source_path = input$source_path,
    source_hash = input$canonical_hash, stream = input$stream$manifest, selection = input$selection,
    output_directory = normalizePath(directory, winslash = "/", mustWork = TRUE))
}

brohn_validate_stream_curation_result <- function(result, input) {
  brohn_require(identical(result$schema, "brohn-stream-extract-result/1.0") && identical(result$operation, "extract_stream") &&
    result$status %in% c("extracted", "needs_attention") && identical(result$source$sha256, input$canonical_hash) &&
    identical(result$source$stream_id, input$stream$manifest$id) && identical(brohn_hash(result$selection), brohn_hash(input$selection)), "Stream curation result changed its input or selection.")
  q <- result$quality
  brohn_require(brohn_number(q$source_rows, 0, 2000000, TRUE) && q$source_rows == input$stream$manifest$sample_count &&
    brohn_number(q$included_rows, 0, q$source_rows, TRUE) && brohn_number(q$excluded_rows, 0, q$source_rows, TRUE) &&
    q$source_rows == q$included_rows+q$excluded_rows && isTRUE(q$source_order_preserved) && isTRUE(q$source_clock_text_preserved) &&
    identical(q$identities_inferred, FALSE) && identical(q$synchronized, FALSE), "Stream curation counts or preservation policy changed.")
  brohn_require(brohn_array(result$segments) && length(result$segments) <= 2000L && q$segment_count == length(result$segments) &&
    sum(vapply(result$segments, function(s) s$sample_count, numeric(1))) == q$included_rows, "Derived segment counts do not reconcile with included samples.")
  brohn_require(identical(result$metadata$segment_column, "brohn_segment_id") && identical(result$metadata$time_column, "brohn_time_s") &&
    identical(result$metadata$time_unit, "s") && identical(result$metadata$participant_column, "brohn_participant_id") &&
    identical(result$metadata$session_column, "brohn_session_id") &&
    identical(unlist(result$metadata$value_columns), paste0("value_", unlist(input$selection$channel_ids))) &&
    identical(as.numeric(result$metadata$sampling_rate), as.numeric(input$selection$sampling_rate)) &&
    identical(result$metadata$unit, brohn_stream_unit(input$selection$unit)), "Derived analysis mapping changed its reviewed channels, unit or independent segment field.")
  brohn_require(brohn_array(result$preview) && length(result$preview) <= min(20, q$included_rows) &&
    brohn_array(result$columns) && !anyDuplicated(unlist(result$columns)), "Derived source preview or columns are invalid.")
  brohn_require(brohn_array(result$artifacts) && length(result$artifacts) == 2L &&
    setequal(vapply(result$artifacts, `[[`, character(1), "kind"), c("curated_signal_csv", "curation_decisions_jsonl")), "Derived signal or full inclusion/exclusion evidence is missing.")
  brohn_require(identical(q$dataset_eligible, identical(result$status, "extracted")) &&
    identical(q$dataset_eligible, any(vapply(result$segments, function(s) s$sample_count >= 2L, logical(1)))), "Derived dataset eligibility disagrees with its segment support.")
  invisible(result)
}

brohn_analyse_stream_curation <- function(input, scratch) {
  request <- brohn_stream_curation_request(input, scratch)
  request_path <- file.path(scratch, "stream-curation-request.json"); result_path <- file.path(scratch, "stream-curation-result.json")
  brohn_write_json_file(request, request_path)
  process <- processx::run(brohn_python_profile("eeg"), c("scripts/workers/stream_extract.py", "--request", request_path, "--output", result_path),
    timeout = 15*60, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  brohn_require(file.exists(result_path), paste("Stream curation returned no result.", substr(process$stderr, 1, 1000)))
  result <- brohn_read_json_file(result_path, maximum = 8*1024^2)
  brohn_require(process$status == 0 && !identical(result$status, "error"), paste("Stream curation needs attention:", brohn_default(result$error$message, substr(process$stderr, 1, 2000))))
  brohn_validate_stream_curation_result(result, input)
  list(title = paste(toupper(input$selection$modality), "from", input$stream$title), stream_curation = result)
}

.brohn_curation_publication_hash <- digest::digest(file="R/platform-stream-curation.R",algo="sha256")
.brohn_publish_stream_curation_legacy <- function(store, output, scratch, job, input, output_path) {
  brohn_store_batch(store, function() {
    brohn_renew_job(store, job$id, job$worker, job$token, 60)
    r <- job$request
    brohn_require(identical(brohn_hash(input$stream), r$stream_hash) && identical(brohn_hash(input$imported), r$import_hash) &&
      identical(brohn_hash(input$dataset), r$dataset_hash) && identical(brohn_hash(input$selection), brohn_hash(r$selection)) &&
      identical(input$canonical_hash, r$canonical_hash) && identical(input$project_id, r$project_id), "Stream curation publication differs from the frozen job request.")
    result <- output$report$stream_curation; brohn_validate_stream_curation_result(result, input)
    promoted <- lapply(result$artifacts, function(a) {
      brohn_require(brohn_number(a$bytes, 0, if (a$kind == "curated_signal_csv") 512*1024^2 else 4*1024^3, TRUE) &&
        brohn_text(a$sha256, 64) && grepl("^[a-f0-9]{64}$", a$sha256), "Invalid curation artifact size/hash.")
      path <- brohn_interchange_checked_path(store, a$path, scratch)
      brohn_require(identical(as.numeric(file.info(path)$size), as.numeric(a$bytes)) && identical(digest::digest(file = path, algo = "sha256"), a$sha256), "A stream curation artifact failed its immutable hash check.")
      if (a$kind == "curation_decisions_jsonl") brohn_require(brohn_interchange_jsonl_count(path) == result$quality$source_rows, "Full inclusion/exclusion evidence is missing source rows.")
      object <- brohn_store_object(store, path = path, media_type = if (a$kind == "curated_signal_csv") "text/csv" else "application/x-ndjson")
      brohn_renew_job(store, job$id, job$worker, job$token, 60)
      c(list(kind = a$kind), object)
    })
    result$artifacts <- promoted
    id <- paste0("stream-curation-", sub("^job-", "", job$id))
    dataset_id <- if (isTRUE(result$quality$dataset_eligible)) paste0("dataset-", id) else NULL
    lineage <- list(stream_id = input$stream$id, stream_revision = input$stream_revision, stream_hash = brohn_hash(input$stream),
      import_id = input$imported$id, import_revision = input$import_revision, import_hash = brohn_hash(input$imported),
      raw_dataset_id = input$dataset$id, raw_dataset_revision = input$dataset_revision, raw_dataset_hash = brohn_hash(input$dataset),
      raw_source = input$dataset$source, canonical_hash = input$canonical_hash, original_stream_artifacts = input$stream$manifest$artifacts,
      source_uid = input$stream$manifest$uid, source_id = input$stream$manifest$source_id)
    processing <- list(job_id = job$id, attempt = job$attempt, recipe = "analogue-stream-curation/1.0", request_hash = brohn_hash(input),
      worker_output_hash = digest::digest(file = output_path, algo = "sha256"), code_hashes = output$code_identity)
    analysis_job <- NULL
    if (!is.null(dataset_id)) {
      csv <- Filter(function(a) a$kind == "curated_signal_csv", promoted)[[1L]]
      source <- csv[c("hash", "size", "media_type")]; source$filename <- paste0(id, ".csv"); source$format <- "csv"
      body <- list(schema_version = "brohn-dataset/1.0.0", id = dataset_id, title = output$report$title,
        modality = input$selection$modality, origin = input$stream$origin, study_id = input$dataset$study_id, study_revision = input$dataset$study_revision,
        source = source, columns = result$columns, preview = result$preview, metadata = result$metadata, status = "accepted", data_revision = 1L, notes = "",
        source_provenance = list(imported_at = brohn_now(), acquisition = "curated_stream", source_hash = source$hash, curation_id = id,
          lineage = lineage, selection = input$selection, quality = result$quality, artifacts = promoted, processing = processing))
      if (isTRUE(input$selection$run_analysis)) {
        body$metadata$parameters <- brohn_stream_standard_parameters(input$selection$modality, input$selection$sampling_rate)
        result$metadata$parameters <- body$metadata$parameters
      }
      brohn_validate_dataset_mapping(body)
      brohn_put_entity(store, "dataset", dataset_id, body, expected_revision = 0L, project_id = input$project_id)
      if (isTRUE(input$selection$run_analysis)) analysis_job <- brohn_queue_dataset(store, dataset_id, revision = 1L)
    }
    body <- list(schema = "brohn-stream-curation/1.0", id = id, dataset_id = dataset_id, source_dataset_id = input$dataset$id,
      stream_id = input$stream$id, title = output$report$title, origin = input$stream$origin, status = result$status,
      lineage = lineage, extraction = result, processing = processing, analysis_job_id = if (!is.null(analysis_job)) analysis_job$id else NULL, created_at = brohn_now())
    publication <- file.path(scratch, "published-stream-curation.json"); brohn_write_json_file(body, publication)
    body$result_object <- brohn_store_object(store, path = publication, media_type = "application/json")
    brohn_put_entity(store, "stream_curation", id, body, expected_revision = 0L, project_id = input$project_id)
    brohn_renew_job(store, job$id, job$worker, job$token, 60)
    brohn_complete_job(store, job$id, job$worker, job$token, list(curation_id = id, dataset_id = dataset_id, analysis_job_id = body$analysis_job_id, status = result$status, output_hash = body$result_object$hash))
  })
}

brohn_publish_stream_curation <- function(store, output, scratch, job, input, output_path) {
  if(.Platform$OS.type!="windows")return(.brohn_publish_stream_curation_legacy(store,output,scratch,job,input,output_path))
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Prepare curation publication outside an enclosing transaction.")
  .brohn_publication_output_identity(output,list("R/platform-stream-curation.R"=.brohn_curation_publication_hash))
  .brohn_publication_job(store,job);r<-job$request
  validate_pin<-function(){
    stream<-brohn_get_entity(store,"stream",input$stream$id,input$stream_revision)
    imported<-brohn_get_entity(store,"stream_import",input$imported$id,input$import_revision)
    dataset<-brohn_get_entity(store,"dataset",input$dataset$id,input$dataset_revision)
    brohn_require(!is.null(stream)&&!is.null(imported)&&!is.null(dataset) &&
      identical(brohn_hash(stream$body),r$stream_hash) && identical(brohn_hash(imported$body),r$import_hash) &&
      identical(brohn_hash(dataset$body),r$dataset_hash) && identical(stream$project_id,r$project_id) &&
      identical(imported$project_id,r$project_id) && identical(dataset$project_id,r$project_id) &&
      identical(brohn_hash(input$stream),r$stream_hash) && identical(brohn_hash(input$imported),r$import_hash) &&
      identical(brohn_hash(input$dataset),r$dataset_hash) && identical(brohn_hash(input$selection),brohn_hash(r$selection)) &&
      identical(input$canonical_hash,r$canonical_hash) && identical(input$project_id,r$project_id),"Stream curation publication differs from the frozen job request.")
  }
  validate_pin();result<-output$report$stream_curation;brohn_validate_stream_curation_result(result,input)
  specs<-lapply(result$artifacts,function(a){
    brohn_require(brohn_number(a$bytes,0,if(a$kind=="curated_signal_csv")512*1024^2 else 4*1024^3,TRUE),"Invalid curation artifact byte count.")
    list(key=a$kind,kind=a$kind,path=brohn_interchange_checked_path(store,a$path,scratch),sha256=a$sha256,bytes=a$bytes,
      media_type=if(a$kind=="curated_signal_csv")"text/csv" else "application/x-ndjson")
  })
  artifact_context<-.brohn_publication_stage(store,job,specs);document_context<-NULL;committed<-FALSE
  on.exit({if(!is.null(document_context))brohn_close_publication(document_context$guard,committed);brohn_close_publication(artifact_context$guard,committed)},add=TRUE)
  checkpoint<-.brohn_publication_checkpoint(store,job)
  brohn_require(brohn_interchange_jsonl_count(artifact_context$paths[["curation_decisions_jsonl"]],checkpoint)==result$quality$source_rows,
    "Full inclusion/exclusion evidence is missing source rows.")
  promoted<-lapply(artifact_context$descriptors,function(x)c(list(kind=x$kind),x[c("hash","size","media_type")]))
  result$artifacts<-promoted;id<-paste0("stream-curation-",sub("^job-","",job$id))
  dataset_id<-if(isTRUE(result$quality$dataset_eligible))paste0("dataset-",id) else NULL
  lineage<-list(stream_id=input$stream$id,stream_revision=input$stream_revision,stream_hash=brohn_hash(input$stream),
    import_id=input$imported$id,import_revision=input$import_revision,import_hash=brohn_hash(input$imported),
    raw_dataset_id=input$dataset$id,raw_dataset_revision=input$dataset_revision,raw_dataset_hash=brohn_hash(input$dataset),
    raw_source=input$dataset$source,canonical_hash=input$canonical_hash,original_stream_artifacts=input$stream$manifest$artifacts,
    source_uid=input$stream$manifest$uid,source_id=input$stream$manifest$source_id)
  processing<-list(job_id=job$id,attempt=job$attempt,recipe="analogue-stream-curation/1.0",request_hash=brohn_hash(input),
    worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity,publication=.brohn_publication_processing(artifact_context))
  dataset<-NULL;analysis_id<-NULL
  if(!is.null(dataset_id)) {
    csv<-Filter(function(a)a$kind=="curated_signal_csv",promoted)[[1L]]
    source<-csv[c("hash","size","media_type")];source$filename<-paste0(id,".csv");source$format<-"csv"
    dataset<-list(schema_version="brohn-dataset/1.0.0",id=dataset_id,title=output$report$title,modality=input$selection$modality,
      origin=input$stream$origin,study_id=input$dataset$study_id,study_revision=input$dataset$study_revision,
      source=source,columns=result$columns,preview=result$preview,metadata=result$metadata,status="accepted",data_revision=1L,notes="",
      source_provenance=list(imported_at=brohn_now(),acquisition="curated_stream",source_hash=source$hash,curation_id=id,
        lineage=lineage,selection=input$selection,quality=result$quality,artifacts=promoted,processing=processing))
    if(isTRUE(input$selection$run_analysis)) {
      dataset$metadata$parameters<-brohn_stream_standard_parameters(input$selection$modality,input$selection$sampling_rate)
      result$metadata$parameters<-dataset$metadata$parameters
      analysis_id<-.brohn_store_id(store$con,"job")
    }
    brohn_validate_dataset_mapping(dataset)
  }
  body<-list(schema="brohn-stream-curation/1.0",id=id,dataset_id=dataset_id,source_dataset_id=input$dataset$id,stream_id=input$stream$id,
    title=output$report$title,origin=input$stream$origin,status=result$status,lineage=lineage,extraction=result,processing=processing,
    analysis_job_id=analysis_id,created_at=brohn_now())
  checkpoint(TRUE)
  document_context<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-stream-curation.json"))
  receipt<-brohn_store_batch(store,function(){
    validate_pin();.brohn_publication_register(store,artifact_context)
    object<-.brohn_publication_register(store,document_context)[[1L]][c("hash","size","media_type")]
    if(!is.null(dataset)) {
      brohn_put_entity(store,"dataset",dataset_id,dataset,expected_revision=0L,project_id=input$project_id)
      if(!is.null(analysis_id)) {
        queued<-brohn_queue_dataset(store,dataset_id,revision=1L,prepared_id=analysis_id)
        brohn_require(identical(queued$id,analysis_id),"The actual dependent job differs from its frozen curation export; publication was rolled back.")
      }
    }
    body$result_object<-object;brohn_put_entity(store,"stream_curation",id,body,expected_revision=0L,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(curation_id=id,dataset_id=dataset_id,analysis_job_id=analysis_id,status=result$status,output_hash=object$hash))
  })
  committed<-TRUE;receipt
}

brohn_stream_curations <- function(store, stream_id = NULL, source_dataset_id = NULL, limit = 500L) {
  filters <- list()
  if (!is.null(stream_id)) filters$stream_id <- stream_id
  if (!is.null(source_dataset_id)) filters$source_dataset_id <- source_dataset_id
  brohn_list_entities(store, "stream_curation", limit = limit, filters = filters)
}
