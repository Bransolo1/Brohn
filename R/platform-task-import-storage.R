# Small immutable protocol registries accompany the independently retained trial
# source. A metadata filepath is never accepted as protocol evidence.
brohn_task_registry_file <- function(path, reference = NULL) {
  brohn_require(brohn_text(path,4096) && file.exists(path) && !dir.exists(path), "The original task protocol registry is unavailable.")
  connection <- file(path,"rb"); on.exit(close(connection),add=TRUE)
  bytes <- readBin(connection,"raw",n=16*1024^2+1L)
  brohn_require(length(bytes)>0L && length(bytes)<=16*1024^2, "Task protocol registries must contain at most 16 MiB of UTF-8 JSON.")
  text <- rawToChar(bytes); Encoding(text) <- "UTF-8"
  brohn_require(!is.na(iconv(text,from="UTF-8",to="UTF-8")), "The task protocol registry must use UTF-8 JSON.")
  registry <- brohn_parse(text,16*1024^2)
  hash <- digest::digest(bytes,algo="sha256",serialize=FALSE)
  canonical_hash <- brohn_hash(registry)
  if(!is.null(reference)) {
    brohn_fields(reference,c("hash","bytes","media_type","filename","canonical_hash","task_definition_hash"),label="Task registry reference")
    brohn_require(identical(hash,reference$hash) && identical(as.numeric(length(bytes)),as.numeric(reference$bytes)) &&
      identical(reference$media_type,"application/json") && identical(canonical_hash,reference$canonical_hash) &&
      identical(brohn_hash(registry$task),reference$task_definition_hash), "The saved task protocol registry failed its byte or definition integrity check.")
  }
  list(registry=registry,bytes=bytes,hash=hash,canonical_hash=canonical_hash)
}
brohn_stage_task_registry <- function(store,path,filename,dataset_id,dataset_revision,study_id,study_revision,task_id) {
  dataset <- brohn_get_entity(store,"dataset",dataset_id)
  brohn_require(!is.null(dataset) && identical(dataset$body$modality,"implicit") &&
    identical(as.numeric(dataset$revision),as.numeric(dataset_revision)), "The task dataset changed. Reopen its current mapping before attaching a registry.")
  brohn_require(brohn_number(study_revision,1,.Machine$integer.max,TRUE), "Choose the original saved study revision.")
  study <- brohn_study(store,study_id,study_revision)
  brohn_require(identical(study$project_id,dataset$project_id), "Choose an original study in this dataset's project.")
  brohn_require(brohn_text(filename,240) && !grepl("[/\\\\]",filename), "Choose a named protocol registry file.")
  original <- brohn_task_registry_file(path)
  brohn_validate_task_protocol_registry(original$registry,study$body,task_id)
  object <- brohn_store_object(store,bytes=original$bytes,media_type="application/json")
  brohn_require(identical(object$hash,original$hash), "The retained protocol registry differs from its reviewed bytes.")
  list(hash=object$hash,bytes=as.numeric(length(original$bytes)),media_type="application/json",filename=filename,
    canonical_hash=original$canonical_hash,task_definition_hash=brohn_hash(original$registry$task))
}
brohn_read_task_registry <- function(store,dataset,design) {
  brohn_validate_task_import_mapping(dataset,design)
  reference <- dataset$metadata$protocol_registry
  brohn_require(is.list(reference), "Attach the original task protocol registry before confirming this mapping.")
  path <- brohn_object_path(store,reference$hash,verify=TRUE)
  original <- brohn_task_registry_file(path,reference)
  brohn_validate_task_protocol_registry(original$registry,design,dataset$metadata$task_id)
  original$registry
}
