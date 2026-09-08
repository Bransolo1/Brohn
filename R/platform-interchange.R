# Multistream normalization is a preservation operation, not a scientific score.
brohn_validate_interchange_mapping <- function(dataset) {
  brohn_require(identical(dataset$modality, "multimodal") && dataset$source$format %in% c("xdf", "json"),
    "Multistream import accepts a recorded XDF or an explicit Brohn stream-bundle JSON file.")
  m <- dataset$metadata
  brohn_require(is.list(m) && brohn_text(m$origin_statement, 4000), "Describe where this multistream recording came from.")
  brohn_require(all(names(m) %in% c("origin_statement", "clock_policy")) && identical(m$clock_policy, "preserve_only"),
    "Confirm original clocks and recorded correction evidence will be preserved without synchronization.")
  brohn_require(dataset$origin %in% c("imported", "sample", "pilot", "live"), "Declare the raw recording origin.")
  invisible(dataset)
}

brohn_queue_multistream <- function(store, dataset_id, revision = NULL, force = FALSE) {
  record <- brohn_get_entity(store, "dataset", dataset_id, revision)
  brohn_require(!is.null(record), "The raw dataset revision is unavailable.")
  brohn_project(store, record$project_id)
  brohn_require(record$body$status %in% c("accepted", "analysed"), "Confirm the multistream source declaration before importing its streams.")
  brohn_validate_interchange_mapping(record$body)
  brohn_object_path(store, record$body$source$hash)
  request <- list(dataset_id = dataset_id, dataset_revision = record$revision, dataset_hash = brohn_hash(record$body),
    source_hash = record$body$source$hash, project_id = record$project_id, recipe = "multistream-preservation/1.0.0")
  key <- paste0("multistream:", brohn_hash(request), if (isTRUE(force)) paste0(":", brohn_id("rerun")) else "")
  brohn_enqueue_job(store, "normalise_dataset", request, key)
}

brohn_interchange_input <- function(store, job) {
  r <- job$request
  record <- brohn_get_entity(store, "dataset", r$dataset_id, r$dataset_revision)
  brohn_require(!is.null(record) && identical(record$project_id, r$project_id) && identical(brohn_hash(record$body), r$dataset_hash) &&
    identical(record$body$source$hash, r$source_hash), "Pinned multistream dataset failed its integrity check.")
  brohn_validate_interchange_mapping(record$body)
  list(schema = "brohn-analysis-input/1.0", operation = "normalise_dataset", dataset = record$body,
    dataset_revision = record$revision, project_id = record$project_id,
    source_path = brohn_object_path(store, record$body$source$hash))
}

brohn_interchange_request <- function(input, scratch) {
  brohn_validate_interchange_mapping(input$dataset)
  directory <- file.path(scratch, "artifacts")
  brohn_require(dir.exists(directory) || dir.create(directory), "Cannot prepare the stream artifact directory.")
  list(schema = "brohn-interchange-request/1.0", operation = "import_multistream",
    format = if (input$dataset$source$format == "xdf") "xdf" else "brohn_stream_bundle",
    source_path = normalizePath(input$source_path, winslash = "/", mustWork = TRUE), source_hash = input$dataset$source$hash,
    output_directory = normalizePath(directory, winslash = "/", mustWork = TRUE),
    metadata = list(origin = input$dataset$origin, origin_statement = input$dataset$metadata$origin_statement, clock_policy = "preserve_only"))
}

brohn_analyse_interchange <- function(input, scratch) {
  request <- brohn_interchange_request(input, scratch)
  request_path <- file.path(scratch, "interchange-request.json"); result_path <- file.path(scratch, "interchange-result.json")
  brohn_write_json_file(request, request_path)
  process <- processx::run(brohn_python_profile("interchange"), c("scripts/workers/interchange.py", "--request", request_path, "--output", result_path),
    timeout = 30*60, echo = FALSE, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  brohn_require(file.exists(result_path), paste("Multistream import returned no result.", substr(process$stderr, 1, 1000)))
  result <- brohn_read_json_file(result_path, maximum = 8*1024^2)
  brohn_require(process$status == 0 && !identical(result$status, "error"), paste("Multistream import needs attention:",
    brohn_default(result$error$message, substr(process$stderr, 1, 2000))))
  brohn_validate_interchange_result(result, input)
  list(title = paste(input$dataset$title, "streams"), dataset_id = input$dataset$id, dataset_revision = input$dataset_revision,
    source_hash = input$dataset$source$hash, origin = result$origin, interchange = result)
}

brohn_interchange_artifact_key <- function(item) paste0(brohn_default(item$stream_id, "@container"), "|", item$kind)

brohn_validate_interchange_result <- function(result, input) {
  brohn_require(identical(result$schema, "brohn-interchange-result/1.0") && identical(result$operation, "import_multistream") &&
    result$status %in% c("imported", "needs_mapping"), "Multistream worker returned an incompatible result.")
  brohn_require(identical(result$source$sha256, input$dataset$source$hash) &&
    identical(as.numeric(result$source$bytes), as.numeric(input$dataset$source$size)), "Multistream result refers to different source bytes.")
  brohn_require(identical(result$source$format, if (input$dataset$source$format == "xdf") "xdf" else "brohn_stream_bundle"), "Multistream result format changed.")
  streams <- result$streams
  brohn_require(brohn_array(streams) && length(streams) >= 1L && length(streams) <= 64L && !anyDuplicated(brohn_ids(streams)), "Invalid normalized stream identities/count.")
  expected <- "@container|container_evidence_json"
  for (stream in streams) {
    brohn_require(identical(stream$schema, "brohn-imported-stream/1.0") && brohn_valid_id(stream$id) &&
      stream$kind %in% c("signal", "markers", "unclassified") && stream$origin %in% c("sample", "imported", "pilot", "live", "mixed", "unclassified"), "Invalid normalized stream manifest.")
    brohn_require(brohn_array(stream$channels) && length(stream$channels) >= 1L && length(stream$channels) <= 256L &&
      !anyDuplicated(brohn_ids(stream$channels)) && brohn_number(stream$sample_count, 0, 2000000, TRUE) &&
      brohn_number(stream$value_count, 0, 20000000, TRUE) && stream$value_count == stream$sample_count*length(stream$channels), "Stream sample/channel counts disagree.")
    brohn_require(brohn_array(stream$preview) && length(stream$preview) <= min(20, stream$sample_count) && stream$preview_count == length(stream$preview), "Stream preview count is invalid.")
    brohn_require(isTRUE(stream$quality$complete_source_samples_retained) && identical(stream$quality$clock_correction_applied, FALSE) &&
      identical(stream$quality$dejitter_applied, FALSE) && identical(stream$quality$calibration_applied, FALSE), "Worker changed the requested source-preservation policy.")
    expected <- c(expected, paste0(stream$id, "|", c("stream_samples_jsonl", "stream_samples_csv", "stream_evidence_jsonl")))
  }
  brohn_require(result$quality$stream_count == length(streams) &&
    result$quality$sample_count == sum(vapply(streams, `[[`, numeric(1), "sample_count")) &&
    result$quality$value_count == sum(vapply(streams, `[[`, numeric(1), "value_count")) &&
    result$quality$sample_count <= 2000000 && result$quality$value_count <= 20000000 &&
    isTRUE(result$quality$complete_source_samples_retained) && identical(result$quality$synchronized, FALSE), "Multistream total counts or clock policy disagree.")
  brohn_require(brohn_array(result$artifacts) && length(result$artifacts) == length(expected), "Multistream artifact manifest is incomplete.")
  actual <- vapply(result$artifacts, brohn_interchange_artifact_key, character(1))
  brohn_require(!anyDuplicated(actual) && setequal(expected, actual), "Missing, extra or duplicate stream artifacts.")
  match_artifact <- function(item) {
    canonical <- result$artifacts[[match(brohn_interchange_artifact_key(item), actual)]]
    brohn_require(!is.null(canonical) && identical(brohn_hash(item), brohn_hash(canonical)), "Nested stream artifact does not match the complete manifest.")
  }
  for (stream in streams) {
    brohn_require(brohn_array(stream$artifacts) && length(stream$artifacts) == 3L &&
      all(vapply(stream$artifacts, function(a) identical(a$stream_id, stream$id), logical(1))), "Stream artifact ownership changed.")
    lapply(stream$artifacts, match_artifact)
  }
  match_artifact(result$container$evidence_artifact)
  invisible(result)
}

brohn_interchange_checked_path <- function(store, path, scratch) {
  brohn_require(brohn_text(path, 4096) && file.exists(path) && !dir.exists(path), "Stream artifact file is unavailable.")
  path <- .brohn_store_contained(store, path)
  directory <- .brohn_store_contained(store, file.path(scratch, "artifacts"))
  compare_path <- path; compare_directory <- directory
  if (.Platform$OS.type == "windows") {compare_path <- tolower(path); compare_directory <- tolower(directory)}
  brohn_require(startsWith(compare_path, paste0(compare_directory, "/")), "Stream artifact leaves this attempt's artifact directory.")
  path
}

brohn_interchange_jsonl_count <- function(path, checkpoint = NULL) {
  connection <- file(path, "rb"); on.exit(close(connection), add = TRUE)
  total <- 0; last <- NULL
  repeat {
    bytes <- readBin(connection, "raw", n = 1024^2)
    if (!length(bytes)) break
    total <- total + sum(bytes == as.raw(10)); last <- tail(bytes, 1L)
    brohn_require(total <= 2000000, "Canonical stream artifact has too many rows.")
    if(!is.null(checkpoint))checkpoint()
  }
  brohn_require(is.null(last) || identical(last, as.raw(10)), "Canonical JSONL ends with an incomplete row.")
  total
}

brohn_promote_interchange_artifacts <- function(store, result, scratch, job, input) {
  brohn_store_batch(store, function() {
    brohn_renew_job(store, job$id, job$worker, job$token, 60)
    brohn_require(identical(input$dataset$id, job$request$dataset_id) &&
      identical(as.numeric(input$dataset_revision), as.numeric(job$request$dataset_revision)) &&
      identical(brohn_hash(input$dataset), job$request$dataset_hash) && identical(input$project_id, job$request$project_id),
      "Artifact publication input does not match the frozen job request.")
    brohn_validate_interchange_result(result, input)
    bytes_total <- 0
    checked <- lapply(result$artifacts, function(a) {
      brohn_require(brohn_number(a$bytes, 0, 4*1024^3, TRUE) && brohn_text(a$sha256, 64) && grepl("^[a-f0-9]{64}$", a$sha256), "Invalid stream artifact size or hash.")
      bytes_total <<- bytes_total + a$bytes
      brohn_require(bytes_total <= 4*1024^3, "Stream artifacts exceed their total bound.")
      path <- brohn_interchange_checked_path(store, a$path, scratch)
      brohn_require(identical(as.numeric(file.info(path)$size), as.numeric(a$bytes)) &&
        identical(digest::digest(file = path, algo = "sha256"), a$sha256), "Stream artifact failed its SHA-256 or size check.")
      if (identical(a$kind, "stream_samples_jsonl")) {
        stream <- brohn_find(result$streams, a$stream_id)
        brohn_require(brohn_interchange_jsonl_count(path) == stream$sample_count, "Canonical stream row count disagrees with the source manifest.")
      } else brohn_require(a$bytes > 0, "Stream metadata and CSV header artifacts cannot be empty.")
      brohn_renew_job(store, job$id, job$worker, job$token, 60)
      a$path <- path; a
    })
    media <- c(stream_samples_jsonl = "application/x-ndjson", stream_samples_csv = "text/csv", stream_evidence_jsonl = "application/x-ndjson", container_evidence_json = "application/json")
    promoted <- lapply(checked, function(a) {
      object <- brohn_store_object(store, path = a$path, media_type = unname(media[[a$kind]]))
      brohn_require(identical(object$hash, a$sha256) && identical(as.numeric(object$size), as.numeric(a$bytes)), "Stream artifact changed during immutable promotion.")
      brohn_renew_job(store, job$id, job$worker, job$token, 60)
      c(list(stream_id = a$stream_id, kind = a$kind), object)
    })
    names_by_key <- vapply(promoted, brohn_interchange_artifact_key, character(1))
    handle <- function(a) promoted[[match(brohn_interchange_artifact_key(a), names_by_key)]]
    result$artifacts <- promoted
    result$streams <- lapply(result$streams, function(s) {s$artifacts <- lapply(s$artifacts, handle); s})
    result$container$evidence_artifact <- handle(result$container$evidence_artifact)
    # Only declared artifact handles have filesystem semantics. Source marker
    # text and user channel IDs must retain their original content unchanged.
    brohn_require(all(vapply(result$artifacts, function(a) is.null(a$path), logical(1))) &&
      all(vapply(result$streams, function(s) all(vapply(s$artifacts, function(a) is.null(a$path), logical(1))), logical(1))), "An ephemeral artifact path survived publication.")
    result
  })
}

.brohn_interchange_publication_hash <- digest::digest(file="R/platform-interchange.R",algo="sha256")
.brohn_publish_stream_import_legacy <- function(store, output, scratch, job, input, output_path) {
  brohn_store_batch(store, function() {
    brohn_renew_job(store, job$id, job$worker, job$token, 60)
    result <- brohn_promote_interchange_artifacts(store, output$report$interchange, scratch, job, input)
    suffix <- sub("^job-", "", job$id)
    id <- paste0("stream-import-", suffix)
    stream_ids <- lapply(seq_along(result$streams), function(i) paste0("stream-", suffix, "-", i))
    for (i in seq_along(result$streams)) {
      stream <- result$streams[[i]]
      body <- list(schema_version = "brohn-normalized-stream/1.0.0", id = stream_ids[[i]], import_id = id,
        title = brohn_default(stream$name, paste("Stream", i)), source_index = i, source_stream_id = stream$id,
        source_dataset_id = input$dataset$id, source_dataset_revision = input$dataset_revision,
        source_hash = input$dataset$source$hash, study_id = input$dataset$study_id,
        origin = stream$origin, status = if (isTRUE(stream$quality$requires_mapping) || isTRUE(stream$origin_conflict) || identical(stream$orderly_closed, FALSE)) "needs_mapping" else "imported",
        review_status = "unreviewed", manifest = stream, created_at = brohn_now())
      brohn_put_entity(store, "stream", body$id, body, project_id = input$project_id)
    }
    body <- list(schema_version = "brohn-stream-import/1.0.0", id = id, title = output$report$title,
      dataset_id = input$dataset$id, dataset_revision = input$dataset_revision, dataset_hash = brohn_hash(input$dataset),
      source = input$dataset$source, raw_origin = input$dataset$origin, origin = result$origin, status = result$status,
      stream_ids = stream_ids, stream_count = length(stream_ids), sample_count = result$quality$sample_count,
      value_count = result$quality$value_count, manifest = result, created_at = brohn_now(),
      processing = list(job_id = job$id, attempt = job$attempt, recipe = "multistream-preservation/1.0.0",
        request_hash = brohn_hash(input), worker_output_hash = digest::digest(file = output_path, algo = "sha256"),
        code_hashes = output$code_identity))
    publication <- file.path(scratch, "published-stream-import.json")
    brohn_write_json_file(list(schema = "brohn-analysis-output/1.0", code_identity = output$code_identity,
      stream_import = body), publication)
    object <- brohn_store_object(store, path = publication, media_type = "application/json")
    body$result_object <- object
    brohn_put_entity(store, "stream_import", id, body, project_id = input$project_id)
    brohn_renew_job(store, job$id, job$worker, job$token, 60)
    brohn_complete_job(store, job$id, job$worker, job$token,
      list(import_id = id, stream_ids = stream_ids, output_hash = object$hash, status = result$status))
  })
}

brohn_publish_stream_import <- function(store, output, scratch, job, input, output_path) {
  if(.Platform$OS.type!="windows")return(.brohn_publish_stream_import_legacy(store,output,scratch,job,input,output_path))
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Prepare stream publication outside an enclosing transaction.")
  .brohn_publication_output_identity(output,list("R/platform-interchange.R"=.brohn_interchange_publication_hash))
  .brohn_publication_job(store,job)
  validate_pin<-function(){
    record<-brohn_get_entity(store,"dataset",job$request$dataset_id,job$request$dataset_revision)
    brohn_require(!is.null(record) && identical(record$project_id,job$request$project_id) && identical(brohn_hash(record$body),job$request$dataset_hash) &&
      identical(input$dataset$id,job$request$dataset_id) && identical(as.numeric(input$dataset_revision),as.numeric(job$request$dataset_revision)) &&
      identical(brohn_hash(input$dataset),job$request$dataset_hash) && identical(input$project_id,job$request$project_id),
      "Artifact publication input does not match the frozen job request.")
  }
  validate_pin();result<-output$report$interchange;brohn_validate_interchange_result(result,input)
  total<-0;media<-c(stream_samples_jsonl="application/x-ndjson",stream_samples_csv="text/csv",stream_evidence_jsonl="application/x-ndjson",container_evidence_json="application/json")
  specs<-lapply(result$artifacts,function(a){
    brohn_require(brohn_number(a$bytes,0,4*1024^3,TRUE),"Invalid stream artifact byte count.")
    total<<-total+a$bytes;brohn_require(total<=4*1024^3,"Stream artifacts exceed their total bound.")
    if(a$kind!="stream_samples_jsonl")brohn_require(a$bytes>0,"Stream metadata and CSV header artifacts cannot be empty.")
    list(key=brohn_interchange_artifact_key(a),kind=a$kind,path=brohn_interchange_checked_path(store,a$path,scratch),
      sha256=a$sha256,bytes=a$bytes,media_type=unname(media[[a$kind]]))
  })
  artifact_context<-.brohn_publication_stage(store,job,specs);document_context<-NULL;committed<-FALSE
  on.exit({if(!is.null(document_context))brohn_close_publication(document_context$guard,committed);brohn_close_publication(artifact_context$guard,committed)},add=TRUE)
  checkpoint<-.brohn_publication_checkpoint(store,job)
  for(a in result$artifacts)if(a$kind=="stream_samples_jsonl") {
    stream<-brohn_find(result$streams,a$stream_id)
    brohn_require(brohn_interchange_jsonl_count(artifact_context$paths[[brohn_interchange_artifact_key(a)]],checkpoint)==stream$sample_count,
      "Canonical stream row count disagrees with the source manifest.")
    checkpoint()
  }
  promoted<-lapply(seq_along(result$artifacts),function(i)c(list(stream_id=result$artifacts[[i]]$stream_id,kind=result$artifacts[[i]]$kind),
    artifact_context$descriptors[[i]][c("hash","size","media_type")]))
  keys<-vapply(promoted,brohn_interchange_artifact_key,character(1))
  handle<-function(a)promoted[[match(brohn_interchange_artifact_key(a),keys)]]
  result$streams<-lapply(result$streams,function(s){s$artifacts<-lapply(s$artifacts,handle);s})
  result$container$evidence_artifact<-handle(result$container$evidence_artifact);result$artifacts<-promoted
  suffix<-sub("^job-","",job$id);id<-paste0("stream-import-",suffix)
  stream_ids<-lapply(seq_along(result$streams),function(i)paste0("stream-",suffix,"-",i))
  stream_bodies<-lapply(seq_along(result$streams),function(i){
    stream<-result$streams[[i]]
    list(schema_version="brohn-normalized-stream/1.0.0",id=stream_ids[[i]],import_id=id,title=brohn_default(stream$name,paste("Stream",i)),
      source_index=i,source_stream_id=stream$id,source_dataset_id=input$dataset$id,source_dataset_revision=input$dataset_revision,
      source_hash=input$dataset$source$hash,study_id=input$dataset$study_id,origin=stream$origin,
      status=if(isTRUE(stream$quality$requires_mapping)||isTRUE(stream$origin_conflict)||identical(stream$orderly_closed,FALSE))"needs_mapping" else "imported",
      review_status="unreviewed",manifest=stream,created_at=brohn_now())
  })
  body<-list(schema_version="brohn-stream-import/1.0.0",id=id,title=output$report$title,dataset_id=input$dataset$id,dataset_revision=input$dataset_revision,
    dataset_hash=brohn_hash(input$dataset),source=input$dataset$source,raw_origin=input$dataset$origin,origin=result$origin,status=result$status,
    stream_ids=stream_ids,stream_count=length(stream_ids),sample_count=result$quality$sample_count,value_count=result$quality$value_count,
    manifest=result,created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,recipe="multistream-preservation/1.0.0",
      request_hash=brohn_hash(input),worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity,
      publication=.brohn_publication_processing(artifact_context)))
  checkpoint(TRUE)
  document_context<-.brohn_publication_stage_json(store,job,list(schema="brohn-analysis-output/1.0",code_identity=output$code_identity,stream_import=body),
    file.path(scratch,"published-stream-import.json"))
  receipt<-brohn_store_batch(store,function(){
    validate_pin();.brohn_publication_register(store,artifact_context)
    object<-.brohn_publication_register(store,document_context)[[1L]][c("hash","size","media_type")]
    for(stream_body in stream_bodies)brohn_put_entity(store,"stream",stream_body$id,stream_body,project_id=input$project_id)
    body$result_object<-object;brohn_put_entity(store,"stream_import",id,body,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(import_id=id,stream_ids=stream_ids,output_hash=object$hash,status=result$status))
  })
  committed<-TRUE;receipt
}

brohn_stream_import <- function(store, id, revision = NULL) {
  record <- brohn_get_entity(store, "stream_import", id, revision)
  brohn_require(!is.null(record), "This preserved multistream import is unavailable.")
  record
}

brohn_stream_imports <- function(store, dataset_id = NULL, project_id = NULL, limit = 500) {
  brohn_list_entities(store, "stream_import", project_id, limit, filters = if (is.null(dataset_id)) list() else list(dataset_id = dataset_id))
}

brohn_streams <- function(store, dataset_id = NULL, import_id = NULL, project_id = NULL, limit = 2000) {
  filters <- list()
  if (!is.null(dataset_id)) filters$source_dataset_id <- dataset_id
  if (!is.null(import_id)) filters$import_id <- import_id
  records <- brohn_list_entities(store, "stream", project_id, limit, filters = filters)
  if (!is.null(import_id)) records <- records[order(vapply(records, function(x) x$body$source_index, numeric(1)))]
  records
}

brohn_stream_artifact <- function(store, stream_id, kind) {
  brohn_require(kind %in% c("stream_samples_jsonl", "stream_samples_csv", "stream_evidence_jsonl"), "Choose canonical data, CSV or clock/metadata evidence.")
  record <- brohn_get_entity(store, "stream", stream_id)
  brohn_require(!is.null(record), "This normalized stream is unavailable.")
  matches <- Filter(function(a) identical(a$kind, kind), record$body$manifest$artifacts)
  brohn_require(length(matches) == 1L, "The stream artifact is unavailable.")
  matches[[1]]
}

brohn_stream_artifact_path <- function(store, stream_id, kind) brohn_object_path(store, brohn_stream_artifact(store, stream_id, kind)$hash)

brohn_download_stream_artifact <- function(store, stream_id, kind, destination) {
  object <- brohn_stream_artifact(store, stream_id, kind)
  brohn_copy_object_download(store, object$hash, destination)
}
