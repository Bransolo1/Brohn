# External candidate only: prepare/recheck exact authorized source references.
# No queue, worker registration, map publication, UI or scientific scoring yet.
.brohn_clock_profile <- "reviewed-two-event-affine/0.1.0-draft"
.brohn_clock_ref <- function(record) list(id=record$id,revision=record$revision,hash=brohn_hash(record$body))
.brohn_clock_reference <- function(store,kind,id,revision,project_id) {
  .brohn_qexplorer_catalog(store,kind,id,revision,project_id)
  current<-brohn_get_entity(store,kind,id)
  record<-brohn_get_entity(store,kind,id,revision)
  brohn_require(!is.null(current)&&!is.null(record)&&!isTRUE(current$body$archived)&&!isTRUE(record$body$archived),
    "A selected original recording/import/stream is archived or unavailable.")
  schema<-switch(kind,dataset="brohn-dataset/1.0.0",stream_import="brohn-stream-import/1.0.0",stream="brohn-normalized-stream/1.0.0")
  brohn_require(!is.null(schema)&&identical(current$body$id,current$id)&&identical(record$body$id,record$id)&&
    identical(current$body$schema_version,schema)&&identical(record$body$schema_version,schema),
    "The original record identity or schema is inconsistent with its catalog entry.")
  record
}
.brohn_clock_select_track <- function(store,selection,kind,dataset,imported,project_id) {
  brohn_fields(selection,c("stream_id","channel_id"),label="Clock preview channel")
  brohn_require(brohn_valid_id(selection$stream_id)&&brohn_text(selection$channel_id,500),"Select an original stream and channel.")
  current<-brohn_get_entity(store,"stream",selection$stream_id)
  brohn_require(!is.null(current),"The selected original stream is unavailable.")
  stream<-.brohn_clock_reference(store,"stream",current$id,current$revision,project_id)
  body<-stream$body;s<-body$manifest;channel<-brohn_find(s$channels,selection$channel_id)
  brohn_require(identical(body$schema_version,"brohn-normalized-stream/1.0.0")&&
    identical(body$import_id,imported$id)&&stream$id %in% unlist(imported$body$stream_ids)&&
    identical(body$source_dataset_id,dataset$id)&&body$source_dataset_revision==dataset$revision&&
    identical(body$source_hash,dataset$body$source$hash)&&identical(body$source_stream_id,s$id),
    "Each channel must belong to the exact selected recording/import and original source.")
  index<-match(stream$id,unlist(imported$body$stream_ids))
  brohn_require(brohn_number(body$source_index,1,length(imported$body$manifest$streams),TRUE)&&body$source_index==index&&
    identical(body$source_stream_id,imported$body$manifest$streams[[index]]$id)&&
    identical(brohn_hash(s),brohn_hash(imported$body$manifest$streams[[index]])),
    "The selected stream differs from its exact position and original manifest in the preserved import.")
  brohn_require(identical(s$kind,kind)&&!is.null(channel)&&identical(s$origin,body$origin)&&
    identical(body$origin,dataset$body$origin)&&!isTRUE(s$origin_conflict),
    "Select an original marker or scalar signal channel with a consistent declared origin.")
  if(kind=="signal")brohn_require(channel$value_type %in% c("float64","float32","int64","int32","int16","int8"),
    "Choose a scalar numeric signal channel.")
  brohn_require(isTRUE(s$quality$complete_source_samples_retained)&&identical(s$quality$clock_correction_applied,FALSE)&&
    identical(s$quality$dejitter_applied,FALSE),"Use preserved original timestamp coordinates without another correction or dejitter step.")
  brohn_require(s$clock$kind %in% c("monotonic","device","unix")&&identical(s$clock$representation,"decimal_string")&&
    s$clock$unit %in% c("s","ms","us","ns","ticks"),"Choose an explicit supported original clock and unit.")
  artifacts<-lapply(c("stream_samples_jsonl","stream_evidence_jsonl"),function(kind){
    selected<-Filter(function(a)identical(a$kind,kind),s$artifacts)
    brohn_require(length(selected)==1L,"The complete original sample and clock-evidence artifacts are required.")
    a<-selected[[1L]];brohn_object_path(store,a$hash,verify=FALSE)
    a[c("hash","size","media_type")]})
  list(id=paste(stream$id,channel$id,sep="/"),stream=.brohn_clock_ref(stream),channel_id=channel$id,
    clock=s$clock,origin=body$origin,kind=kind,samples=artifacts[[1L]],evidence=artifacts[[2L]])
}
.brohn_clock_select_recording <- function(store,selection,project_id) {
  brohn_fields(selection,c("dataset_id","import_id","marker","tracks"),label="Clock preview recording")
  brohn_require(brohn_valid_id(selection$dataset_id)&&brohn_valid_id(selection$import_id)&&
    brohn_array(selection$tracks)&&length(selection$tracks)>=1L&&length(selection$tracks)<=2L,
    "Choose one preserved recording/import and one or two signal channels.")
  head<-brohn_get_entity(store,"dataset",selection$dataset_id)
  imported<-brohn_stream_import(store,selection$import_id)
  brohn_require(!is.null(head)&&identical(head$project_id,project_id)&&identical(head$body$modality,"multimodal")&&
    !isTRUE(head$body$archived)&&identical(imported$project_id,project_id)&&identical(imported$body$dataset_id,head$id),
    "Choose a preserved multistream recording/import in this project.")
  head<-.brohn_clock_reference(store,"dataset",head$id,head$revision,project_id)
  imported<-.brohn_clock_reference(store,"stream_import",imported$id,imported$revision,project_id)
  dataset<-.brohn_clock_reference(store,"dataset",head$id,imported$body$dataset_revision,project_id)
  brohn_require(identical(brohn_hash(dataset$body),imported$body$dataset_hash)&&
    identical(dataset$body$source$hash,imported$body$source$hash)&&
    identical(dataset$body$origin,imported$body$origin)&&dataset$body$origin %in% c("sample","pilot","live","imported"),
    "The preserved import must match its original recording revision, bytes and declared origin.")
  brohn_object_path(store,dataset$body$source$hash,verify=FALSE)
  retained<-imported$body$result_object
  brohn_require(is.list(retained)&&brohn_text(retained$hash,64)&&brohn_number(retained$size,1,16*1024^2),
    "The original preserved import result is required for this clock profile.")
  brohn_object_path(store,retained$hash,verify=FALSE)
  marker<-.brohn_clock_select_track(store,selection$marker,"markers",dataset,imported,project_id)
  tracks<-lapply(selection$tracks,function(t).brohn_clock_select_track(store,t,"signal",dataset,imported,project_id))
  selected<-c(list(marker),tracks)
  brohn_require(!anyDuplicated(vapply(selected,`[[`,character(1),"id")),"Choose distinct original stream/channel tracks.")
  brohn_require(length(unique(vapply(selected,function(t)brohn_hash(t$clock),character(1))))==1L,
    "Signals and markers need the same explicit recording clock on each side.")
  list(dataset=.brohn_clock_ref(dataset),dataset_head=.brohn_clock_ref(head),imported=.brohn_clock_ref(imported),
    original_source=dataset$body$source[c("hash","size","media_type")],retained_import=retained[c("hash","size","media_type")],
    origin=dataset$body$origin,marker=marker,tracks=tracks)
}
.brohn_clock_pairs <- function(pairs,minimum,maximum,label) {
  brohn_require(brohn_array(pairs)&&length(pairs)>=minimum&&length(pairs)<=maximum,paste(label,"count is outside its bound."))
  for(pair in pairs){brohn_fields(pair,c("source_sequence","reference_sequence"),label=label)
    brohn_require(brohn_number(pair$source_sequence,1,2000000,TRUE)&&brohn_number(pair$reference_sequence,1,2000000,TRUE),
      "Select exact original marker row numbers; typed times are not recorded event evidence.")}
  invisible(pairs)
}
brohn_prepare_clock_preview <- function(store,source,reference,anchors,checks,review,project_id) {
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);brohn_project(store,project_id)
  brohn_fields(review,c("confirmed","rationale"),label="Reviewed clock relationship")
  brohn_require(isTRUE(review$confirmed)&&brohn_text(review$rationale,4000)&&nzchar(trimws(review$rationale)),
    "Confirm the event correspondences and explain the relationship between recordings.")
  .brohn_clock_pairs(anchors,2L,2L,"Defining anchors");.brohn_clock_pairs(checks,0L,16L,"Held-out events")
  both<-c(anchors,checks)
  for(name in c("source_sequence","reference_sequence"))brohn_require(!anyDuplicated(vapply(both,`[[`,numeric(1),name)),
    "Defining and held-out events must use distinct original rows on each side.")
  sides<-list(source=.brohn_clock_select_recording(store,source,project_id),reference=.brohn_clock_select_recording(store,reference,project_id))
  brohn_require(!identical(sides$source$dataset$id,sides$reference$dataset$id)&&
    !identical(sides$source$imported$id,sides$reference$imported$id),"Choose two distinct recordings/imports.")
  brohn_require(identical(sides$source$origin,sides$reference$origin),"Keep sample, pilot, live and imported recordings separate.")
  list(schema="brohn-clock-preview-job/0.1",profile=.brohn_clock_profile,project_id=project_id,
    selections=list(source=source,reference=reference),recordings=sides,anchors=anchors,checks=checks,review=review)
}
brohn_clock_preview_input <- function(store,request,verify=TRUE) {
  brohn_fields(request,c("schema","profile","project_id","selections","recordings","anchors","checks","review"),label="Pinned clock preview")
  brohn_require(identical(request$schema,"brohn-clock-preview-job/0.1")&&identical(request$profile,.brohn_clock_profile),"Unsupported clock preview profile.")
  brohn_fields(request$selections,c("source","reference"),label="Pinned recording selections")
  fresh<-brohn_prepare_clock_preview(store,request$selections$source,request$selections$reference,request$anchors,request$checks,request$review,request$project_id)
  brohn_require(identical(brohn_hash(fresh),brohn_hash(request)),"The selected sources changed after preview selection. Review a new preview.")
  objects<-list()
  artifact<-function(a){objects[[length(objects)+1L]]<<-list(hash=a$hash,bytes=a$size)
    list(path=brohn_object_path(store,a$hash,verify=verify),hash=a$hash,bytes=a$size)}
  track<-function(ref){stream<-brohn_get_entity(store,"stream",ref$stream$id,ref$stream$revision);s<-stream$body$manifest
    list(id=ref$id,source_stream_id=s$id,kind=s$kind,origin=stream$body$origin,channel=brohn_find(s$channels,ref$channel_id),
      clock=s$clock,preservation=s$quality,sample_count=s$sample_count,segment_count=s$segment_count,
      samples=artifact(ref$samples),evidence=artifact(ref$evidence))}
  side<-function(r){artifact(r$original_source)
    retained<-artifact(r$retained_import);original<-brohn_read_json_file(retained$path)
    imported<-brohn_get_entity(store,"stream_import",r$imported$id,r$imported$revision)
    fields<-c("schema_version","id","dataset_id","dataset_revision","dataset_hash","source","raw_origin","origin",
      "stream_ids","stream_count","sample_count","value_count","manifest","processing")
    brohn_require(identical(original$schema,"brohn-analysis-output/1.0")&&is.list(original$stream_import)&&
      all(fields %in% names(original$stream_import))&&all(fields %in% names(imported$body))&&
      identical(brohn_hash(original$stream_import[fields]),brohn_hash(imported$body[fields])),
      "The selected import differs from its retained original source manifest and publication provenance.")
    list(dataset=r$dataset,imported=r$imported,marker=track(r$marker),tracks=lapply(r$tracks,track))}
  worker<-list(schema="brohn-clock-preview-input/0.1",source=side(request$recordings$source),reference=side(request$recordings$reference),
    anchors=request$anchors,checks=request$checks,review=request$review)
  list(schema="brohn-analysis-input/1.0",operation="clock_preview_candidate",project_id=request$project_id,
    binding=request,preview=worker,source_objects=objects)
}
