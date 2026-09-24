# Exact saved-video audio derivation. This profile never scores a research outcome.
.brohn_audio_extraction_loaded<-stats::setNames(lapply(c("R/platform-audio-extraction.R","scripts/workers/audio_extract.py"),
  function(p)digest::digest(file=p,algo="sha256")),c("R/platform-audio-extraction.R","scripts/workers/audio_extract.py"))
.brohn_ax_profile<-"video-audio-source/1.0"
.brohn_ax_ref<-function(r)list(id=r$id,revision=r$revision,hash=.brohn_sv_hash(r$body))
.brohn_ax_sha<-function(x)brohn_text(x,64)&&grepl("^[a-f0-9]{64}$",x)
.brohn_ax_refs<-function(refs){out<-list();for(r in refs){brohn_require(.brohn_ax_sha(r$hash)&&brohn_number(r$bytes,1,512*1024^2,TRUE),"An audio derivation source reference is invalid.")
  old<-Filter(function(o)identical(o$hash,r$hash),out);if(length(old))brohn_require(old[[1]]$bytes==r$bytes,"Source byte references disagree.")else out[[length(out)+1L]]<-r};out}
.brohn_ax_camera<-function(store,d,verify) {
  p<-d$body$source_provenance
  if(!identical(p$acquisition,"browser_camera")) {
    brohn_require(is.null(p$capture_id)&&is.null(p$capture_policy)&&is.null(p$run_id),"A camera source cannot discard its original capture lineage.")
    return(list(binding=NULL,source_refs=list()))
  }
  brohn_require(all(c("camera_captures","delivery_runs")%in%DBI::dbListTables(store$con)),"The original camera consent and run are unavailable.")
  capture<-.brohn_camera_decode(.brohn_camera_row(store,id=p$capture_id));publication<-brohn_get_entity(store,"camera_capture",p$capture_id)
  run<-brohn_run(store,p$run_id)
  brohn_require(!is.null(capture)&&!is.null(publication)&&!is.null(run)&&identical(capture$project_id,d$project_id)&&
    identical(publication$project_id,d$project_id)&&identical(capture$run_id,p$run_id)&&identical(publication$body$dataset_id,d$id)&&
    identical(publication$body$source_hash,d$body$source$hash),"The video no longer belongs to its original camera publication and project.")
  a<-publication$body$assembly;start<-capture$start
  brohn_validate_camera_policy(start$policy)
  brohn_require(identical(capture$status,"completed")&&isTRUE(capture$final$container_complete)&&isTRUE(start$request$consented)&&
    isTRUE(start$policy$audio)&&isTRUE(start$request$settings$audio)&&identical(run$completion_status,"completed")&&identical(run$transfer_status,"saved"),
    "Audio derivation requires a completed consented camera recording with audio requested and received, and a completed saved participant run.")
  brohn_require(identical(.brohn_sv_hash(capture),publication$body$capture_hash)&&identical(a$capture_hash,publication$body$capture_hash)&&
    .brohn_sv_same(a$start,start$request)&&.brohn_sv_same(a$final,capture$final)&&.brohn_sv_same(a$policy,start$policy)&&
    .brohn_sv_same(p$capture_policy,start$policy)&&.brohn_sv_same(p$decoder,a$decoder)&&isTRUE(a$decoder$supported)&&
    identical(start$study_id,d$body$study_id)&&identical(start$origin,d$body$origin)&&identical(start$design_hash,run$protocol$design_hash)&&
    identical(start$protocol_hash,.brohn_sv_hash(run$protocol))&&identical(run$protocol$design$project_id,d$project_id)&&
    .brohn_sv_same(start$policy,run$protocol$design$camera),"The camera source changed its frozen consent, protocol, outcome or assembled evidence.")
  audio<-Filter(function(s)identical(s$codec_type,"audio"),a$decoder$streams)
  brohn_require(length(audio)==1L&&brohn_number(a$decoder$audio_frames,1,100000,TRUE)&&
    brohn_number(audio[[1]]$index,0,1023,TRUE)&&brohn_text(audio[[1]]$codec_name,64),"The assembled camera recording has no verified received audio track.")
  brohn_require(!is.null(publication$body$result_object)&&.brohn_sv_same(p$artifacts,publication$body$artifacts),"Camera publication lacks its exact retained source manifest.")
  retained<-.brohn_sv_retained(store,publication,"camera_capture",verify)
  list(binding=list(capture_id=capture$id,capture_hash=.brohn_sv_hash(capture),publication=.brohn_ax_ref(publication),run_id=run$id,
    protocol_hash=start$protocol_hash,design_hash=start$design_hash,policy=start$policy,participant_id=start$participant_id,
    audio_stream=list(stream_index=audio[[1]]$index,codec=audio[[1]]$codec_name)),
    source_refs=c(list(retained),lapply(p$artifacts,function(x)list(hash=x$hash,bytes=x$size))))
}
brohn_audio_extraction_source<-function(store,id,revision,hash,project_id,verify=TRUE,require_head=FALSE) {
  brohn_project(store,project_id);.brohn_qexplorer_catalog(store,"dataset",id,revision,project_id)
  d<-brohn_get_entity(store,"dataset",id,revision);head<-brohn_get_entity(store,"dataset",id)
  brohn_require(!is.null(d)&&!is.null(head)&&identical(d$project_id,project_id)&&identical(head$project_id,project_id)&&identical(.brohn_sv_hash(d$body),hash),
    "Choose the exact saved video dataset in its current project.")
  b<-d$body
  brohn_require(identical(b$modality,"video")&&b$source$format%in%c("mp4","mov","mkv","webm","avi")&&
    identical(b$source$hash,b$source_provenance$source_hash)&&identical(head$body$source$hash,b$source$hash)&&
    identical(head$body$origin,b$origin)&&identical(head$body$study_id,b$study_id)&&.brohn_sv_same(head$body$source_provenance,b$source_provenance),
    "This video source, origin or acquisition lineage changed. Open the current original source.")
  if(require_head)brohn_require(head$revision==revision&&identical(.brohn_sv_hash(head$body),hash),"The selected video revision changed. Inspect its current tracks again.")
  if(!is.null(b$study_id)){study<-brohn_get_entity(store,"study",b$study_id);brohn_require(!is.null(study)&&identical(study$project_id,project_id),"The original video study moved or is unavailable.")}
  brohn_require(brohn_number(b$source$size,1,512*1024^2,TRUE),"Audio extraction accepts saved videos up to 512 MiB.")
  path<-brohn_object_path(store,b$source$hash,verify=verify);brohn_require(file.info(path)$size==b$source$size,"The original video byte count changed.")
  camera<-.brohn_ax_camera(store,d,verify)
  refs<-.brohn_ax_refs(c(list(list(hash=b$source$hash,bytes=b$source$size)),camera$source_refs))
  if(verify)for(ref in refs)brohn_object_path(store,ref$hash,verify=TRUE)
  list(dataset=d,source_path=path,camera=camera$binding,source_refs=refs)
}
brohn_prepare_audio_extraction<-function(store,dataset_id,revision,hash,project_id,operation="audio_tracks",catalog=NULL,stream_index=NULL,require_head=TRUE) {
  brohn_require(operation%in%c("audio_tracks","audio_extract"),"Choose audio track inspection or extraction.")
  s<-brohn_audio_extraction_source(store,dataset_id,revision,hash,project_id,FALSE,require_head)
  ref<-selection<-NULL
  if(operation=="audio_extract"){
    brohn_require(is.list(catalog)&&brohn_number(stream_index,0,1023,TRUE),"Inspect audio tracks, then explicitly select a container stream.")
    saved<-brohn_audio_extraction_record(store,catalog$id,project_id,verify=FALSE)
    brohn_require(saved$revision==catalog$revision&&identical(.brohn_sv_hash(saved$body),catalog$hash)&&
      identical(saved$body$request$operation,"audio_tracks")&&.brohn_sv_same(saved$body$request$dataset,.brohn_ax_ref(s$dataset)),
      "The selected track inventory belongs to another video revision.")
    matches<-Filter(function(t)t$stream_index==stream_index,saved$body$result$tracks)
    brohn_require(length(matches)==1L,"The chosen audio stream is absent from this exact inventory.")
    ref<-.brohn_ax_ref(saved);selection<-list(stream_index=as.integer(stream_index))
  }else brohn_require(is.null(catalog)&&is.null(stream_index),"Track inspection cannot silently select a stream.")
  list(schema="brohn-audio-extraction-job/1.0",profile=.brohn_ax_profile,operation=operation,project_id=project_id,
    dataset=.brohn_ax_ref(s$dataset),dataset_id=dataset_id,study_id=s$dataset$body$study_id,origin=s$dataset$body$origin,
    source_hash=s$dataset$body$source$hash,source_bytes=s$dataset$body$source$size,camera=s$camera,catalog=ref,selection=selection)
}
brohn_queue_audio_extraction<-function(store,dataset_id,revision,hash,project_id,operation="audio_tracks",catalog=NULL,stream_index=NULL,retry=FALSE) {
  request<-brohn_prepare_audio_extraction(store,dataset_id,revision,hash,project_id,operation,catalog,stream_index)
  brohn_enqueue_job(store,operation,request,paste0(operation,":",brohn_hash(request),if(retry)paste0(":",brohn_id("retry"))else""))
}
brohn_audio_extraction_input<-function(store,job,verify=TRUE,require_head=TRUE) {
  r<-job$request
  brohn_fields(r,c("schema","profile","operation","project_id","dataset","dataset_id","study_id","origin","source_hash","source_bytes","camera","catalog","selection"),label="Audio extraction job")
  brohn_require(identical(r$schema,"brohn-audio-extraction-job/1.0")&&identical(r$profile,.brohn_ax_profile)&&identical(job$operation,r$operation),"Choose a registered audio extraction request.")
  expected<-brohn_prepare_audio_extraction(store,r$dataset$id,r$dataset$revision,r$dataset$hash,r$project_id,r$operation,r$catalog,r$selection$stream_index,require_head)
  brohn_require(.brohn_sv_same(r,expected),"Audio extraction substituted its original source, stream, consent or project.")
  s<-brohn_audio_extraction_source(store,r$dataset$id,r$dataset$revision,r$dataset$hash,r$project_id,verify,require_head)
  refs<-s$source_refs
  if(!is.null(r$catalog)){c<-brohn_get_entity(store,"audio_extraction",r$catalog$id,r$catalog$revision);refs<-c(refs,list(.brohn_sv_retained(store,c,"audio_extraction",verify)))}
  list(schema="brohn-analysis-input/1.0",operation=job$operation,project_id=r$project_id,origin=r$origin,binding=r,
    source_path=s$source_path,source_hash=r$source_hash,source_objects=.brohn_ax_refs(refs))
}
brohn_validate_audio_extraction<-function(result,input) {
  r<-input$binding;operation<-if(r$operation=="audio_tracks")"inspect"else"extract"
  brohn_require(identical(result$schema,"brohn-audio-extract-result/1.0")&&identical(result$profile,.brohn_ax_profile)&&
    identical(result$operation,operation)&&.brohn_sv_same(result$binding,r)&&identical(result$source$sha256,r$source_hash)&&result$source$bytes==r$source_bytes&&
    .brohn_sv_same(result$selection,r$selection),"Audio extraction changed its source binding, operation or selected stream.")
  brohn_require(brohn_array(result$tracks)&&length(result$tracks)<=64L&&!anyDuplicated(vapply(result$tracks,function(t)as.numeric(t$stream_index),numeric(1))),"Audio track inventory is invalid.")
  for(t in result$tracks)brohn_require(brohn_number(t$stream_index,0,1023,TRUE)&&brohn_number(t$sampling_rate,1000,384000,TRUE)&&brohn_number(t$channels,1,64,TRUE)&&
    brohn_text(t$codec,64)&&brohn_text(t$time_base,32)&&grepl("^[0-9]+/[0-9]+$",t$time_base),"An audio track has unsupported identity or dimensions.")
  if(!is.null(r$camera))brohn_require(length(result$tracks)==1L&&result$tracks[[1]]$stream_index==r$camera$audio_stream$stream_index&&
    identical(result$tracks[[1]]$codec,r$camera$audio_stream$codec),"The current audio inventory differs from the assembled consented camera stream.")
  brohn_require(.brohn_ax_sha(result$engine$ffprobe$sha256)&&brohn_text(result$engine$ffprobe$version,500),"Audio extraction lacks the original probe identity.")
  if(operation=="inspect")brohn_require(is.null(result$recording)&&length(result$artifacts)==0L,"Inspection cannot create a recording.")else{
    rec<-result$recording;chosen<-Filter(function(t)t$stream_index==r$selection$stream_index,result$tracks)
    brohn_require(length(chosen)==1L&&.brohn_sv_same(rec[names(chosen[[1]])],chosen[[1]])&&
      brohn_number(rec$samples_per_channel,1,20000000,TRUE)&&rec$samples_per_channel*rec$channels<=20000000&&brohn_number(rec$frame_count,1,500000,TRUE)&&
      identical(rec$unit,"FS")&&identical(rec$sample_format,"float64")&&identical(rec$channel_mixing,"none")&&identical(rec$resampling,"none")&&identical(rec$gap_filling,"none")&&
      identical(rec$sample_zero_definition,"first decoded retained audio sample")&&identical(rec$clock_status,"consistent_within_container_precision"),"Decoded audio changed dimensions, sample policy or timestamp support.")
    finite_string<-function(x)brohn_text(x,100)&&is.finite(suppressWarnings(as.numeric(x)))
    brohn_require(all(vapply(rec[c("source_start_pts_ticks","source_start_time_s","sample_duration_s","maximum_pts_residual_s","pts_consistency_tolerance_s")],finite_string,logical(1)))&&
      as.numeric(rec$maximum_pts_residual_s)>=0&&as.numeric(rec$maximum_pts_residual_s)<=as.numeric(rec$pts_consistency_tolerance_s)&&
      abs(as.numeric(rec$sample_duration_s)-rec$samples_per_channel/rec$sampling_rate)<=1e-10*max(1,rec$samples_per_channel/rec$sampling_rate),"The decoded sample clock or timestamp ledger support changed.")
    brohn_require(length(result$artifacts)==2L&&.brohn_ax_sha(result$engine$ffmpeg$sha256),"Decoded audio needs both complete artifacts and its decoder identity.")
    for(i in 1:2){a<-result$artifacts[[i]];brohn_require(identical(a$kind,c("decoded-audio","audio-frame-ledger")[[i]])&&identical(a$path,c("audio.wav","audio-frames.csv")[[i]])&&
      .brohn_ax_sha(a$sha256)&&brohn_number(a$bytes,1,192*1024^2,TRUE),"A decoded audio artifact is incomplete or outside its bound.")}
  }
  invisible(result)
}
brohn_analyse_audio_extraction<-function(input,scratch) {
  r<-input$binding;directory<-file.path(scratch,"artifacts")
  request<-list(schema="brohn-audio-extract-request/1.0",operation=if(input$operation=="audio_tracks")"inspect"else"extract",binding=r,
    source_path=input$source_path,source_hash=input$source_hash,selection=if(is.null(r$selection))NULL else list(stream_index=as.integer(r$selection$stream_index)),output_directory=directory)
  rp<-file.path(scratch,"audio-extraction-request.json");out<-file.path(scratch,"audio-extraction-result.json");brohn_write_json_file(request,rp)
  child<-processx::run(brohn_python_profile("audio"),c("scripts/workers/audio_extract.py","--input",rp,"--output",out),timeout=15*60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  diagnostics<-strsplit(child$stderr,"\n",fixed=TRUE)[[1L]]
  diagnostics<-diagnostics[nzchar(trimws(diagnostics))]
  reason<-if(length(diagnostics))tail(diagnostics,1L)else "The decoder did not produce a complete retained result."
  brohn_require(child$status==0&&file.exists(out),paste("Video audio needs attention:",substr(reason,1,1200)))
  result<-brohn_read_json_file(out);brohn_validate_audio_extraction(result,input);list(audio_extraction=result)
}
brohn_publish_audio_extraction<-function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Prepare audio derivation outside an enclosing transaction.")
  .brohn_publication_output_identity(output,.brohn_audio_extraction_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(.brohn_sv_same(input,brohn_audio_extraction_input(store,job))&&.brohn_sv_same(output,brohn_read_json_file(output_path)),"Audio source authority or worker output changed before publication.")
  result<-output$report$audio_extraction;brohn_validate_audio_extraction(result,input)
  artifacts<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(artifacts))brohn_close_publication(artifacts$guard,committed)},add=TRUE)
  if(length(result$artifacts))artifacts<-.brohn_publication_stage(store,job,lapply(result$artifacts,function(a)list(key=a$kind,kind=a$kind,
    path=brohn_checked_artifact_path(store,file.path(scratch,"artifacts",a$path),scratch),sha256=a$sha256,bytes=a$bytes,media_type=if(a$kind=="decoded-audio")"audio/wav"else"text/csv")))
  id<-paste0("audio-extraction-",job$id);derived_id<-if(job$operation=="audio_extract")paste0("dataset-",id)else NULL
  objects<-if(is.null(artifacts))list()else lapply(artifacts$descriptors,function(a)c(list(kind=a$kind),a[c("hash","size","media_type")]))
  b<-list(schema="brohn-saved-audio-extraction/1.0",id=id,parent_dataset_id=input$binding$dataset$id,derived_dataset_id=derived_id,
    study_id=input$binding$study_id,origin=input$origin,request=job$request,result=result,artifacts=objects,created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  document<-.brohn_publication_stage_json(store,job,b,file.path(scratch,"published-audio-extraction.json"))
  receipt<-brohn_store_batch(store,function(){
    brohn_require(.brohn_sv_same(input,brohn_audio_extraction_input(store,job,verify=FALSE)),"Audio source, consent or project changed before publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    if(!is.null(artifacts)).brohn_publication_register(store,artifacts)
    b$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    extraction<-brohn_put_entity(store,"audio_extraction",id,b,expected_revision=0L,project_id=input$project_id)
    if(!is.null(derived_id)){
      original<-brohn_get_entity(store,"dataset",input$binding$dataset$id,input$binding$dataset$revision);wav<-objects[[1L]]
      source<-c(wav[c("hash","size","media_type")],list(filename="decoded-audio.wav",format="wav"))
      body<-list(schema_version="brohn-dataset/1.0.0",id=derived_id,title=paste0(substr(original$body$title,1,180)," - audio stream ",result$selection$stream_index),
        modality="audio",origin=input$origin,study_id=original$body$study_id,study_revision=original$body$study_revision,source=source,columns=list(),preview=list(),
        metadata=list(unit="FS",origin_statement=paste("Decoded audio from saved video",original$id,"stream",result$selection$stream_index,". Select an original channel before acoustic analysis; container time is not physical synchronization.")),
        status="needs_mapping",data_revision=1L,notes="",source_provenance=list(imported_at=brohn_now(),source_hash=wav$hash,acquisition="video_audio_extraction",
          extraction=.brohn_ax_ref(extraction),parent_dataset=input$binding$dataset,parent_source_hash=input$source_hash,camera=input$binding$camera,
          recording=result$recording,artifacts=objects,timing_alignment="not_established",physically_qualified=FALSE))
      brohn_put_entity(store,"dataset",derived_id,body,expected_revision=0L,project_id=input$project_id)
    }
    brohn_complete_job(store,job$id,job$worker,job$token,list(audio_extraction_id=id,dataset_id=brohn_default(derived_id,input$binding$dataset$id),parent_dataset_id=input$binding$dataset$id,output_hash=b$result_object$hash))
  });committed<-TRUE;receipt
}
brohn_audio_extraction_record<-function(store,id,project_id,verify=FALSE) {
  r<-brohn_get_entity(store,"audio_extraction",id)
  brohn_require(!is.null(r)&&identical(r$project_id,project_id)&&identical(r$body$schema,"brohn-saved-audio-extraction/1.0"),"The saved extraction is unavailable in this project.")
  .brohn_qexplorer_catalog(store,"audio_extraction",id,r$revision,project_id)
  input<-brohn_audio_extraction_input(store,list(operation=r$body$request$operation,request=r$body$request),verify,require_head=FALSE)
  brohn_validate_audio_extraction(r$body$result,input)
  brohn_require(length(r$body$artifacts)==length(r$body$result$artifacts),"The extraction artifacts are incomplete.")
  for(i in seq_along(r$body$artifacts)){a<-r$body$artifacts[[i]];native<-r$body$result$artifacts[[i]]
    brohn_require(identical(a$kind,native$kind)&&identical(a$hash,native$sha256)&&a$size==native$bytes,"The retained extraction artifact changed.")
    brohn_object_path(store,a$hash,verify=verify)}
  brohn_require(!is.null(r$body$result_object),"This extraction lacks its original retained receipt.")
  .brohn_sv_retained(store,r,"audio_extraction",verify);r
}
brohn_audio_extraction_lineage<-function(store,dataset_record,verify=FALSE) {
  p<-dataset_record$body$source_provenance
  original<-brohn_get_entity(store,"dataset",dataset_record$id,1L)
  derived_identity<-grepl("^dataset-audio-extraction-job[-_]",dataset_record$id)||
    identical(original$body$source_provenance$acquisition,"video_audio_extraction")
  if(!identical(p$acquisition,"video_audio_extraction")){
    brohn_require(!derived_identity,"A derived audio dataset cannot discard its original extraction lineage.");return(NULL)
  }
  brohn_require(derived_identity&&!is.null(original)&&.brohn_sv_same(p,original$body$source_provenance),"Audio derivation lineage is fixed at its original publication, not supplied by a mapping form.")
  ref<-p$extraction;r<-brohn_audio_extraction_record(store,ref$id,dataset_record$project_id,verify)
  brohn_require(r$revision==ref$revision&&identical(.brohn_sv_hash(r$body),ref$hash)&&identical(r$body$derived_dataset_id,dataset_record$id)&&
    identical(dataset_record$body$modality,"audio")&&identical(dataset_record$body$source$format,"wav")&&
    identical(dataset_record$body$source$hash,r$body$artifacts[[1L]]$hash)&&identical(p$source_hash,dataset_record$body$source$hash)&&
    identical(dataset_record$body$origin,r$body$origin)&&identical(dataset_record$body$study_id,r$body$study_id)&&.brohn_sv_same(p$parent_dataset,r$body$request$dataset)&&
    identical(p$parent_source_hash,r$body$request$source_hash)&&.brohn_sv_same(p$camera,r$body$request$camera)&&
    .brohn_sv_same(p$recording,r$body$result$recording)&&.brohn_sv_same(p$artifacts,r$body$artifacts),"Derived audio no longer matches its exact source, channel layout, extraction or acquisition lineage.")
  input<-brohn_audio_extraction_input(store,list(operation=r$body$request$operation,request=r$body$request),verify,require_head=FALSE)
  list(binding=list(extraction=.brohn_ax_ref(r),parent_dataset=p$parent_dataset,parent_source_hash=p$parent_source_hash,camera=p$camera,recording=p$recording),
    source_refs=.brohn_ax_refs(c(input$source_objects,list(.brohn_sv_retained(store,r,"audio_extraction",verify)),lapply(r$body$artifacts,function(a)list(hash=a$hash,bytes=a$size)))))
}
