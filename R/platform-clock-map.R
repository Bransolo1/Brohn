# EXTERNAL candidate. No loader, operation, worker or UI registration.
# Accepted-preview publication is an integration dependency, not implemented by
# inserting a made-up completed job. Tests label injected preview records.
.brohn_clock_map_source_file <- normalizePath("R/platform-clock-map.R",winslash="/",mustWork=TRUE)
.brohn_clock_map_loaded <- digest::digest(file=.brohn_clock_map_source_file,algo="sha256")
.brohn_cm_same <- function(a,b) identical(brohn_hash(a),brohn_hash(b))
.brohn_cm_hash <- function(x) brohn_text(x,64)&&grepl("^[a-f0-9]{64}$",x)
.brohn_cm_ref <- function(x) list(id=x$id,revision=x$revision,hash=brohn_hash(x$body))
.brohn_cm_ref_valid <- function(x) {
  brohn_fields(x,c("id","revision","hash"),label="Exact clock record")
  brohn_require(brohn_valid_id(x$id)&&brohn_number(x$revision,1,1e9,TRUE)&&.brohn_cm_hash(x$hash),"Choose an exact saved clock record revision and hash.")
}
brohn_clock_map_runtime <- function(python,arithmetic_helper,validator,scratch_parent) {
  paths<-lapply(list(python=python,arithmetic_helper=arithmetic_helper,validator=validator,scratch_parent=scratch_parent),
    function(p)normalizePath(p,winslash="/",mustWork=TRUE))
  brohn_require(!dir.exists(paths$python)&&!dir.exists(paths$arithmetic_helper)&&!dir.exists(paths$validator)&&dir.exists(paths$scratch_parent),
    "Configure explicit Python, exact arithmetic helper, validator and an external scratch parent.")
  paths$identity<-list(schema="brohn-clock-map-validator/0.1",r_sha256=.brohn_clock_map_loaded,
    arithmetic_sha256=digest::digest(file=paths$arithmetic_helper,algo="sha256"),validator_sha256=digest::digest(file=paths$validator,algo="sha256"))
  paths
}
.brohn_cm_math <- function(result,input,runtime) {
  check_code<-function()brohn_require(identical(digest::digest(file=.brohn_clock_map_source_file,algo="sha256"),.brohn_clock_map_loaded)&&
    identical(digest::digest(file=runtime$arithmetic_helper,algo="sha256"),runtime$identity$arithmetic_sha256)&&
    identical(digest::digest(file=runtime$validator,algo="sha256"),runtime$identity$validator_sha256),"Clock validation implementation changed; restart before continuing.")
  check_code();folder<-tempfile("clock-math-",tmpdir=runtime$scratch_parent);brohn_require(dir.create(folder),"Cannot create bounded clock-validation scratch.")
  folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
  brohn_require(startsWith(tolower(folder),paste0(tolower(normalizePath(runtime$scratch_parent,winslash="/",mustWork=TRUE)),"/")),"Clock scratch escaped its configured parent.")
  on.exit(unlink(folder,recursive=TRUE),add=TRUE)
  paths<-file.path(folder,c("input.json","result.json","check.json"))
  brohn_write_json_file(input$preview,paths[[1L]],maximum=1024^2);brohn_write_json_file(result,paths[[2L]],maximum=1024^2)
  child<-processx::run(runtime$python,c("-B",runtime$validator,runtime$arithmetic_helper,paths),timeout=15,
    error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(child$status==0L&&file.exists(paths[[3L]]),paste("Exact clock coordinates were not accepted:",substr(child$stderr,1,1000)))
  receipt<-brohn_read_json_file(paths[[3L]],maximum=16384)
  brohn_require(identical(receipt$schema,"brohn-clock-math-check/0.1")&&isTRUE(receipt$passed)&&
    identical(receipt$request_sha256,digest::digest(file=paths[[1L]],algo="sha256"))&&
    identical(receipt$result_sha256,digest::digest(file=paths[[2L]],algo="sha256"))&&
    identical(receipt$helper_sha256,runtime$identity$arithmetic_sha256)&&
    identical(receipt$scope,"schema_and_exact_arithmetic_consistency_only_not_original_source_reinspection"),"Clock arithmetic proof does not bind these exact input/result bytes.")
  check_code();invisible(receipt)
}
brohn_validate_clock_preview_result <- function(result,input,runtime) {
  brohn_require(identical(input$operation,"clock_preview_candidate")&&identical(input$binding$profile,.brohn_clock_profile),"Use a pinned source-qualified clock preview input.")
  brohn_require(nchar(brohn_json(result),type="bytes")<=1024^2,"Clock preview result exceeds one MiB.")
  brohn_fields(result,c("schema","profile","scope","review","identity","origin","recordings","anchors","checks","mapping",
    "physical_synchronization","event_equivalence","uncertainty","authorization","scientific_scoring"),label="Clock preview result")
  brohn_require(identical(result$schema,"brohn-clock-preview/0.1")&&identical(result$profile,input$binding$profile)&&
    identical(result$scope,"source_qualified_preview_component_only")&&.brohn_cm_same(result$review,input$binding$review)&&
    identical(result$physical_synchronization,"not_established")&&identical(result$event_equivalence,"researcher_declared_only")&&
    identical(result$uncertainty,"unknown")&&identical(result$authorization,"requires_current_R_source_project_and_publication_guards")&&
    identical(result$scientific_scoring,"not_performed"),"Clock preview changed its profile, reviewed relationship or interpretation limits.")
  brohn_fields(result$identity,c("participant_id","session_id"),label="Preserved clock identity")
  brohn_require(all(vapply(result$identity,function(x)brohn_text(x,500)&&nzchar(trimws(x)),logical(1))),"Clock preview requires explicit preserved person and visit identities.")
  brohn_fields(result$recordings,c("source","reference"),label="Clock preview recordings")
  for(side in c("source","reference")) {
    got<-result$recordings[[side]];expected<-input$preview[[side]];binding<-input$binding$recordings[[side]]
    brohn_fields(got,c("dataset","imported","clock","tracks"),label="Clock recording result")
    brohn_require(.brohn_cm_same(got$dataset,expected$dataset)&&.brohn_cm_same(got$imported,expected$imported)&&
      .brohn_cm_same(got$clock,expected$marker$clock)&&identical(result$origin,binding$origin),"Clock result substituted an original recording/import/clock or origin.")
    tracks<-c(list(expected$marker),expected$tracks)
    brohn_require(brohn_array(got$tracks)&&length(got$tracks)==length(tracks),"Clock result omitted an inspected original track.")
    for(i in seq_along(tracks)) {
      t<-got$tracks[[i]];s<-tracks[[i]]
      brohn_fields(t,c("id","source_stream_id","channel_id","kind","samples","evidence","source_rows","segment_count","missing_values","unplaced_rows","timestamp_stage","upstream_timestamp_processing"),label="Clock track evidence")
      brohn_require(identical(t$id,s$id)&&identical(t$source_stream_id,s$source_stream_id)&&identical(t$channel_id,s$channel$id)&&identical(t$kind,s$kind)&&
        .brohn_cm_same(t$samples,s$samples[c("hash","bytes")])&&.brohn_cm_same(t$evidence,s$evidence[c("hash","bytes")])&&
        brohn_number(t$source_rows,1,2000000,TRUE)&&t$source_rows==s$sample_count&&brohn_number(t$segment_count,1,t$source_rows,TRUE)&&t$segment_count==s$segment_count&&
        brohn_number(t$missing_values,0,t$source_rows,TRUE)&&brohn_number(t$unplaced_rows,0,t$source_rows,TRUE)&&
        identical(t$timestamp_stage,"importer_preserved_coordinates")&&identical(t$upstream_timestamp_processing,"unknown_unless_separately_source_declared"),
        "Clock result changed complete source counts, channel or artifact identity.")
    }
  }
  brohn_require(brohn_array(result$anchors)&&length(result$anchors)==2L&&brohn_array(result$checks)&&length(result$checks)==length(input$binding$checks),"Clock result changed selected defining/check event counts.")
  pairs<-c(result$anchors,result$checks);selected<-c(input$binding$anchors,input$binding$checks)
  for(i in seq_along(pairs)) {
    brohn_fields(pairs[[i]],c("source","reference","comparison"),label="Clock event pair")
    for(side in c("source","reference")) {
      event<-pairs[[i]][[side]];marker<-input$preview[[side]]$marker
      brohn_fields(event,c("source_sequence","source_segment","source_timestamp","timestamp_unit","clock_id","channel_id","value_json","value_state","identity"),label="Original clock event")
      brohn_fields(event$identity,c("participant_id","session_id"),c("condition_id","exposure_id"),label="Original anchor identity")
      brohn_require(all(vapply(event$identity,function(x)is.null(x)||brohn_text(x,500,empty=TRUE),logical(1))),"Original anchor identity is malformed.")
      brohn_require(brohn_number(event$source_sequence,1,marker$sample_count,TRUE)&&event$source_sequence==selected[[i]][[paste0(side,"_sequence")]]&&
        brohn_text(event$source_segment,1000)&&brohn_text(event$source_timestamp,120)&&identical(event$timestamp_unit,marker$clock$unit)&&
        identical(event$clock_id,marker$clock$id)&&identical(event$channel_id,marker$channel$id)&&.brohn_cm_same(event$identity[c("participant_id","session_id")],result$identity)&&
        brohn_text(event$value_json,4096)&&jsonlite::validate(event$value_json)&&!identical(trimws(event$value_json),"null")&&identical(event$value_state,"observed"),
        "Clock preview substituted an event row, identity, source timestamp, unit or observed value.")
    }
  }
  # This establishes exact schema/math consistency, not a second source scan.
  .brohn_cm_math(result,input,runtime);invisible(result)
}
.brohn_cm_pin <- function(store,kind,ref,project_id) {
  .brohn_cm_ref_valid(ref);record<-.brohn_clock_reference(store,kind,ref$id,ref$revision,project_id)
  brohn_require(.brohn_cm_same(.brohn_cm_ref(record),ref),"A pinned clock source revision changed.");record
}
# Historical read differs intentionally from pending preview freshness: it pins
# original revisions while freshly checking current project/archive authority.
brohn_clock_map_source_input <- function(store,request,verify=TRUE) {
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,request$project_id);brohn_project(store,request$project_id)
  brohn_fields(request,c("schema","profile","project_id","selections","recordings","anchors","checks","review"),label="Saved clock request")
  brohn_require(identical(request$schema,"brohn-clock-preview-job/0.1")&&identical(request$profile,.brohn_clock_profile),"Unsupported historical clock profile.")
  brohn_fields(request$recordings,c("source","reference"),label="Saved recording bindings")
  brohn_fields(request$selections,c("source","reference"),label="Saved recording choices")
  .brohn_clock_pairs(request$anchors,2L,2L,"Defining anchors");.brohn_clock_pairs(request$checks,0L,16L,"Held-out events")
  brohn_fields(request$review,c("confirmed","rationale"),label="Saved relationship")
  brohn_require(isTRUE(request$review$confirmed)&&brohn_text(request$review$rationale,4000)&&nzchar(trimws(request$review$rationale)),"Saved relationship was not explicitly reviewed.")
  pairs<-c(request$anchors,request$checks)
  for(name in c("source_sequence","reference_sequence"))brohn_require(!anyDuplicated(vapply(pairs,`[[`,numeric(1),name)),"Saved defining and held-out rows overlap.")
  objects<-list()
  object<-function(a){brohn_fields(a,c("hash","size","media_type"),label="Original clock object")
    brohn_require(.brohn_cm_hash(a$hash)&&brohn_number(a$size,0,4*1024^3,TRUE)&&brohn_text(a$media_type,256),"Invalid original clock object reference.")
    path<-brohn_object_path(store,a$hash,verify=verify);brohn_require(file.info(path)$size==a$size,"Original clock object size changed.")
    objects[[length(objects)+1L]]<<-list(hash=a$hash,bytes=a$size);list(path=path,hash=a$hash,bytes=a$size)}
  side<-function(name) {
    r<-request$recordings[[name]];selection<-request$selections[[name]]
    brohn_fields(r,c("dataset","dataset_head","imported","original_source","retained_import","origin","marker","tracks"),label="Pinned clock recording")
    brohn_fields(selection,c("dataset_id","import_id","marker","tracks"),label="Pinned clock selection")
    dataset<-.brohn_cm_pin(store,"dataset",r$dataset,request$project_id)
    head<-.brohn_cm_pin(store,"dataset",r$dataset_head,request$project_id)
    imported<-.brohn_cm_pin(store,"stream_import",r$imported,request$project_id)
    brohn_require(identical(dataset$id,head$id)&&identical(dataset$id,selection$dataset_id)&&identical(imported$id,selection$import_id)&&
      identical(dataset$body$modality,"multimodal")&&identical(imported$body$dataset_id,dataset$id)&&imported$body$dataset_revision==dataset$revision&&
      identical(imported$body$dataset_hash,brohn_hash(dataset$body))&&identical(r$origin,dataset$body$origin)&&identical(r$origin,imported$body$origin)&&
      r$origin %in% c("sample","pilot","live","imported")&&.brohn_cm_same(r$original_source,dataset$body$source[c("hash","size","media_type")])&&
      .brohn_cm_same(imported$body$source,dataset$body$source)&&.brohn_cm_same(r$retained_import,imported$body$result_object[c("hash","size","media_type")]),
      "Saved clock recordings no longer bind their exact original dataset/import sources.")
    object(r$original_source);retained<-object(r$retained_import);original<-brohn_read_json_file(retained$path,maximum=16*1024^2)
    fields<-c("schema_version","id","dataset_id","dataset_revision","dataset_hash","source","raw_origin","origin","stream_ids","stream_count","sample_count","value_count","manifest","processing")
    brohn_require(identical(original$schema,"brohn-analysis-output/1.0")&&is.list(original$stream_import)&&all(fields %in% names(original$stream_import))&&
      all(fields %in% names(imported$body))&&.brohn_cm_same(original$stream_import[fields],imported$body[fields]),"Saved clock import differs from its retained original publication.")
    track<-function(ref,sel,kind) {
      brohn_fields(ref,c("id","stream","channel_id","clock","origin","kind","samples","evidence"),label="Pinned clock track")
      brohn_fields(sel,c("stream_id","channel_id"),label="Pinned channel choice")
      stream<-.brohn_cm_pin(store,"stream",ref$stream,request$project_id);b<-stream$body;s<-b$manifest
      index<-match(stream$id,unlist(imported$body$stream_ids));channel<-brohn_find(s$channels,ref$channel_id)
      brohn_require(!is.na(index)&&brohn_number(b$source_index,1,length(imported$body$manifest$streams),TRUE)&&index==b$source_index&&
        identical(stream$id,sel$stream_id)&&identical(ref$channel_id,sel$channel_id)&&identical(ref$id,paste(stream$id,ref$channel_id,sep="/"))&&
        identical(b$import_id,imported$id)&&identical(b$source_dataset_id,dataset$id)&&b$source_dataset_revision==dataset$revision&&
        identical(b$source_hash,dataset$body$source$hash)&&identical(b$source_stream_id,s$id)&&.brohn_cm_same(s,imported$body$manifest$streams[[index]])&&
        identical(ref$kind,kind)&&identical(s$kind,kind)&&!is.null(channel)&&identical(ref$origin,r$origin)&&identical(b$origin,r$origin)&&identical(s$origin,r$origin)&&
        !isTRUE(s$origin_conflict)&&.brohn_cm_same(ref$clock,s$clock),"Historical clock track lost exact recording/import/channel membership.")
      brohn_require(isTRUE(s$quality$complete_source_samples_retained)&&identical(s$quality$clock_correction_applied,FALSE)&&identical(s$quality$dejitter_applied,FALSE)&&
        s$clock$kind %in% c("monotonic","device","unix")&&identical(s$clock$representation,"decimal_string")&&s$clock$unit %in% c("s","ms","us","ns","ticks"),"Historical clock coordinates are unsupported.")
      if(kind=="signal")brohn_require(channel$value_type %in% c("float64","float32","int64","int32","int16","int8"),"Historical signal channel is not scalar numeric.")
      for(k in c("samples","evidence")){a<-Filter(function(a)identical(a$kind,paste0("stream_",k,"_jsonl")),s$artifacts)
        brohn_require(length(a)==1L&&.brohn_cm_same(ref[[k]],a[[1L]][c("hash","size","media_type")]),"Historical stream replaced its original artifacts.")}
      list(id=ref$id,source_stream_id=s$id,kind=s$kind,origin=b$origin,channel=channel,clock=s$clock,preservation=s$quality,
        sample_count=s$sample_count,segment_count=s$segment_count,samples=object(ref$samples),evidence=object(ref$evidence))
    }
    brohn_require(brohn_array(r$tracks)&&length(r$tracks)>=1L&&length(r$tracks)<=2L&&length(r$tracks)==length(selection$tracks),"Saved signal choices changed.")
    marker<-track(r$marker,selection$marker,"markers");tracks<-lapply(seq_along(r$tracks),function(i)track(r$tracks[[i]],selection$tracks[[i]],"signal"))
    all<-c(list(marker),tracks)
    brohn_require(!anyDuplicated(vapply(all,`[[`,character(1),"id"))&&length(unique(vapply(all,function(t)brohn_hash(t$clock),character(1))))==1L,"Historical tracks do not share their recorded clock or are duplicated.")
    list(dataset=r$dataset,imported=r$imported,marker=marker,tracks=tracks)
  }
  preview<-list(schema="brohn-clock-preview-input/0.1",source=side("source"),reference=side("reference"),anchors=request$anchors,checks=request$checks,review=request$review)
  brohn_require(!identical(preview$source$dataset$id,preview$reference$dataset$id)&&!identical(preview$source$imported$id,preview$reference$imported$id)&&
    identical(request$recordings$source$origin,request$recordings$reference$origin),"Saved map mixes recording identity or origin.")
  list(schema="brohn-analysis-input/1.0",operation="clock_preview_candidate",project_id=request$project_id,binding=request,preview=preview,source_objects=objects)
}
.brohn_cm_record <- function(store,kind,ref,project_id,verify=TRUE) {
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);brohn_project(store,project_id);.brohn_cm_ref_valid(ref)
  .brohn_qexplorer_catalog(store,kind,ref$id,ref$revision,project_id)
  current<-brohn_get_entity(store,kind,ref$id);record<-brohn_get_entity(store,kind,ref$id,ref$revision)
  schema<-if(kind=="clock_preview")"brohn-saved-clock-preview/0.1" else "brohn-saved-clock-map/0.1"
  brohn_require(!is.null(current)&&!is.null(record)&&!isTRUE(current$body$archived)&&!isTRUE(record$body$archived)&&
    identical(current$body$id,current$id)&&identical(record$body$id,record$id)&&identical(current$body$schema,schema)&&identical(record$body$schema,schema)&&
    .brohn_cm_same(.brohn_cm_ref(record),ref),"Saved clock record is unavailable, inconsistent or no longer authorized.")
  a<-record$body$result_object
  brohn_require(is.list(a)&&.brohn_cm_hash(a$hash)&&brohn_number(a$size,1,2*1024^2,TRUE),"Saved clock record lacks its bounded immutable result object.")
  path<-brohn_object_path(store,a$hash,verify=verify)
  brohn_require(file.info(path)$size==a$size&&.brohn_cm_same(brohn_read_json_file(path,maximum=2*1024^2),record$body[setdiff(names(record$body),"result_object")]),"Saved clock record differs from its retained immutable object.")
  if(kind=="clock_preview")brohn_clock_preview_job_proof(store,record)
  record
}
# A proof-shaped body or a fixture record is not an accepted preview. Production
# readers require the actual completed supervised job and its exact publication.
brohn_clock_preview_job_proof <- function(store,record) {
  b<-record$body;p<-b$processing
  brohn_require(is.list(p)&&brohn_valid_id(p$job_id)&&brohn_number(p$attempt,1,1e9,TRUE)&&.brohn_cm_hash(p$worker_output_hash)&&
    is.list(p$code_hashes)&&length(p$code_hashes)>0L&&brohn_text(b$created_at,128)&&identical(b$origin,b$result$origin),
    "This preview has no complete supervised publication provenance; prepare an accepted preview.")
  job<-brohn_get_job(store,p$job_id)
  brohn_require(!is.null(job)&&identical(job$operation,"preview_clock_alignment")&&identical(job$status,"succeeded")&&job$attempt==p$attempt&&
    identical(b$id,paste0("clock-preview-",job$id))&&identical(job$result$clock_preview_id,record$id)&&identical(job$result$output_hash,b$result_object$hash),
    "The preview is not the exact published result of a succeeded clock-preview job.")
  r<-job$request
  brohn_fields(r,c("schema","project_id","preview","implementation"),optional="authority",label="Original preview dispatch")
  brohn_require(identical(r$schema,"brohn-clock-preview-dispatch/0.1")&&identical(r$project_id,record$project_id)&&
    identical(r$project_id,b$request$project_id)&&.brohn_cm_same(r$preview,b$request)&&is.list(r$implementation)&&length(r$implementation)>0L&&
    !is.null(names(r$implementation))&&!anyDuplicated(names(r$implementation))&&all(nzchar(names(r$implementation)))&&
    all(vapply(r$implementation,.brohn_cm_hash,logical(1)))&&
    all(vapply(names(r$implementation),function(path)identical(r$implementation[[path]],p$code_hashes[[path]]),logical(1))),
    "The preview substituted its frozen job request, project or processing implementation.")
  brohn_require(identical(b$implementation$r_sha256,r$implementation[["R/platform-clock-map.R"]])&&
    identical(b$implementation$arithmetic_sha256,r$implementation[["scripts/workers/clock_affine.py"]])&&
    identical(b$implementation$validator_sha256,r$implementation[["scripts/workers/validate_clock_preview_math.py"]]),
    "The preview validator identity differs from its queued and executed implementation.")
  invisible(job)
}
# The future guarded supervised publisher must be the only production writer
# of clock_preview records. This module deliberately provides no seed/publisher.
brohn_clock_map_preview <- function(store,ref,project_id,runtime,fresh=TRUE,verify=TRUE) {
  record<-.brohn_cm_record(store,"clock_preview",ref,project_id,verify)
  b<-record$body
  brohn_fields(b,c("schema","id","request","result","implementation","result_object"),optional=c("processing","created_at","origin"),label="Accepted clock preview")
  if(!is.null(b$processing)){
    p<-b$processing;brohn_fields(p,c("job_id","attempt","worker_output_hash","code_hashes"),label="Preview processing provenance")
    brohn_require(brohn_valid_id(p$job_id)&&brohn_number(p$attempt,1,1e9,TRUE)&&.brohn_cm_hash(p$worker_output_hash)&&
      is.list(p$code_hashes)&&length(p$code_hashes)>0L&&!is.null(names(p$code_hashes))&&!anyDuplicated(names(p$code_hashes))&&all(nzchar(names(p$code_hashes)))&&
      all(vapply(p$code_hashes,.brohn_cm_hash,logical(1))),"Preview processing provenance is malformed.")
  }
  if(!is.null(b$created_at))brohn_require(brohn_text(b$created_at,128),"Preview creation time is malformed.")
  if(!is.null(b$origin))brohn_require(identical(b$origin,b$result$origin),"Preview origin differs from preserved sources.")
  brohn_fields(b$implementation,c("schema","r_sha256","arithmetic_sha256","validator_sha256"),label="Preview implementation identity")
  brohn_require(identical(b$implementation$schema,"brohn-clock-map-validator/0.1")&&
    all(vapply(b$implementation[c("r_sha256","arithmetic_sha256","validator_sha256")],.brohn_cm_hash,logical(1)))&&
    (!fresh||.brohn_cm_same(b$implementation,runtime$identity))&&identical(b$request$project_id,project_id),"Preview implementation/project differs; prepare a current accepted preview.")
  input<-if(fresh)brohn_clock_preview_input(store,b$request,verify)else brohn_clock_map_source_input(store,b$request,verify)
  brohn_validate_clock_preview_result(b$result,input,runtime)
  original_input<-input
  input$source_objects<-c(input$source_objects,list(list(hash=b$result_object$hash,bytes=b$result_object$size)))
  list(record=record,input=input,original_input=original_input)
}
.brohn_cm_family <- function(request,result) {
  sides<-lapply(request$recordings,function(r)list(dataset=r$dataset,import_id=r$imported$id,retained_import=r$retained_import,
    tracks=lapply(c(list(r$marker),r$tracks),function(t)t[c("id","channel_id","clock","origin","kind","samples","evidence")])))
  list(profile=request$profile,recordings=sides,identity=result$identity,origin=result$origin)
}
.brohn_cm_hold <- function(store,input)brohn_hold_signal_value_sources(store,input)
.brohn_cm_guard_check <- function(guards)for(g in guards).Call(g$native$check,g$pointer)
.brohn_cm_write <- function(store,body,expected_revision,project_id,operation_id,input,recheck,.transaction=NULL) {
  if(!is.null(.transaction)){brohn_fields(.transaction,c("fence","complete"),label="Internal map save transaction")
    brohn_require(is.function(.transaction$fence)&&is.function(.transaction$complete),"Internal map save callbacks are invalid.");.transaction$fence()}
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Save clock maps outside an enclosing writer transaction.")
  guards<-.brohn_cm_hold(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  recheck(TRUE)
  object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(body))),media_type="application/json")
  output_guard<-.brohn_qexplorer_hold(brohn_object_path(store,object$hash,verify=TRUE),object$size)
  on.exit(.brohn_qexplorer_release(output_guard),add=TRUE);body$result_object<-object
  brohn_store_batch(store,function(){recheck(FALSE);.brohn_cm_guard_check(c(guards,list(output_guard)))
    if(!is.null(.transaction)).transaction$fence()
    saved<-brohn_put_entity(store,"clock_map",body$id,body,expected_revision,project_id,operation_id)
    if(!is.null(.transaction)).transaction$complete(saved)
    saved})
}
brohn_save_clock_map <- function(store,preview_ref,title,project_id,map_id,expected_revision,operation_id,runtime,.transaction=NULL) {
  brohn_require(brohn_text(title,240)&&nzchar(trimws(title))&&brohn_valid_id(map_id)&&brohn_valid_id(operation_id)&&brohn_number(expected_revision,0,1e9,TRUE),"Name the reviewed alignment and retain its exact save operation and revision.")
  preview<-brohn_clock_map_preview(store,preview_ref,project_id,runtime)
  b<-preview$record$body;family<-.brohn_cm_family(b$request,b$result);previous<-NULL
  write_input<-preview$input;previous_preview<-NULL
  if(expected_revision>0){old<-brohn_get_entity(store,"clock_map",map_id,expected_revision)
    brohn_require(!is.null(old),"Reopen the exact previous map version before editing.")
    old<-brohn_clock_map_record(store,.brohn_cm_ref(old),project_id,runtime)
    brohn_require(.brohn_cm_same(old$body$family,family),"A map revision must retain its original recording/import/channel family; save a different map for different sources.")
    previous<-.brohn_cm_ref(old)
    previous_preview<-old$body$preview
    prior_preview<-.brohn_cm_record(store,"clock_preview",previous_preview,project_id)
    write_input$source_objects<-c(write_input$source_objects,lapply(list(old$body$result_object,prior_preview$body$result_object),function(a)list(hash=a$hash,bytes=a$size)))}
  body<-list(schema="brohn-saved-clock-map/0.1",id=map_id,title=title,profile=b$request$profile,family=family,previous=previous,
    preview=preview_ref,request=b$request,result=b$result,implementation=b$implementation)
  recheck<-function(verify){now<-brohn_clock_preview_input(store,b$request,verify)
    brohn_require(.brohn_cm_same(now,preview$original_input),"Preview sources changed before the map could be saved.")
    .brohn_cm_record(store,"clock_preview",preview_ref,project_id,verify)
    if(!is.null(previous)){.brohn_cm_record(store,"clock_map",previous,project_id,verify)
      .brohn_cm_record(store,"clock_preview",previous_preview,project_id,verify)}
    invisible(TRUE)}
  .brohn_cm_write(store,body,expected_revision,project_id,operation_id,write_input,recheck,.transaction)
}
brohn_clock_map_record <- function(store,ref,project_id,runtime,verify=TRUE) {
  record<-.brohn_cm_record(store,"clock_map",ref,project_id,verify);b<-record$body
  brohn_fields(b,c("schema","id","title","profile","family","previous","preview","request","result","implementation","result_object"),label="Saved clock map")
  brohn_require(brohn_text(b$title,240)&&nzchar(trimws(b$title))&&identical(b$profile,b$request$profile)&&identical(b$request$project_id,project_id),"Saved map title/profile/project is inconsistent.")
  preview<-brohn_clock_map_preview(store,b$preview,project_id,runtime,fresh=FALSE,verify=verify)
  brohn_require(.brohn_cm_same(b$request,preview$record$body$request)&&.brohn_cm_same(b$result,preview$record$body$result)&&
    .brohn_cm_same(b$implementation,preview$record$body$implementation)&&.brohn_cm_same(b$family,.brohn_cm_family(b$request,b$result)),"Saved map substituted its accepted preview or original source family.")
  if(!is.null(b$previous)){
    prior<-.brohn_cm_record(store,"clock_map",b$previous,project_id,verify)
    brohn_require(identical(prior$id,record$id)&&prior$revision<record$revision&&.brohn_cm_same(prior$body$family,b$family),"Saved map version chain changed identity or sources.")}
  record
}
brohn_rename_clock_map <- function(store,id,expected_revision,title,project_id,operation_id,runtime,.transaction=NULL) {
  brohn_require(brohn_valid_id(id)&&brohn_valid_id(operation_id)&&brohn_number(expected_revision,1,1e9,TRUE)&&
    brohn_text(title,240)&&nzchar(trimws(title)),"Name the saved alignment and retain its exact revision/save operation.")
  old<-brohn_get_entity(store,"clock_map",id,expected_revision);brohn_require(!is.null(old),"Reopen the exact map revision before renaming.")
  ref<-.brohn_cm_ref(old);old<-brohn_clock_map_record(store,ref,project_id,runtime)
  input<-brohn_clock_map_source_input(store,old$body$request)
  original_input<-input
  preview<-.brohn_cm_record(store,"clock_preview",old$body$preview,project_id)
  input$source_objects<-c(input$source_objects,lapply(list(old$body$result_object,preview$body$result_object),function(a)list(hash=a$hash,bytes=a$size)))
  body<-old$body[setdiff(names(old$body),"result_object")];body$title<-title;body$previous<-ref
  recheck<-function(verify){now<-brohn_clock_map_source_input(store,body$request,verify)
    brohn_require(.brohn_cm_same(now,original_input),"Original map source authority changed while renaming.")
    .brohn_cm_record(store,"clock_map",ref,project_id,verify);.brohn_cm_record(store,"clock_preview",body$preview,project_id,verify);invisible(TRUE)}
  .brohn_cm_write(store,body,expected_revision,project_id,operation_id,input,recheck,.transaction)
}
