# Original container PTS review; never rescores an acoustic report or maps external clocks.
.brohn_mr_profile<-"saved-container-media-review/1.0"
.brohn_mr_files<-c("R/platform-media-review.R","scripts/workers/media_review.py","scripts/workers/media_pixels.py","scripts/workers/audio_extract.py")
.brohn_media_review_loaded<-setNames(lapply(.brohn_mr_files,function(p)digest::digest(file=p,algo="sha256")),.brohn_mr_files)
.brohn_mr_ref<-function(r)list(id=r$id,revision=r$revision,hash=.brohn_sv_hash(r$body))
.brohn_mr_same<-function(a,b)identical(.brohn_sv_hash(a),.brohn_sv_hash(b))
.brohn_mr_refs<-function(refs)unname(refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))])
.brohn_mr_sha<-function(x)brohn_text(x,64)&&grepl("^[a-f0-9]{64}$",x)
brohn_media_review_source<-function(store,reference,project_id,verify=FALSE) {
  brohn_fields(reference,c("id","revision","hash"),label="Saved audio window")
  brohn_require(brohn_valid_id(reference$id)&&brohn_number(reference$revision,1,1e9,TRUE)&&.brohn_mr_sha(reference$hash),"Choose an exact saved audio window.")
  .brohn_qexplorer_catalog(store,"audio_review",reference$id,reference$revision,project_id)
  record<-brohn_get_entity(store,"audio_review",reference$id,reference$revision)
  brohn_require(!is.null(record)&&identical(.brohn_sv_hash(record$body),reference$hash),"The saved audio window changed.")
  b<-record$body;r<-brohn_audio_review_record(store,record$id,b$report_id,project_id,verify)
  brohn_require(.brohn_mr_same(.brohn_mr_ref(r),reference)&&identical(r$project_id,project_id)&&!is.null(b$request$extraction_lineage),"This audio window needs preserved derivation from its original video.")
  job<-brohn_get_job(store,b$processing$job_id)
  brohn_require(identical(job$status,"succeeded")&&identical(job$operation,"audio_review")&&identical(job$result$audio_review_id,r$id)&&
    identical(job$result$output_hash,b$result_object$hash)&&.brohn_mr_same(job$request,b$request),"The saved waveform has no matching successful worker publication.")
  # brohn_audio_review_record already validates the original input/result contract.
  # Resolve its current authority once more for the full source refs, rather than
  # reconstructing that same input (which itself resolves this source twice).
  s<-brohn_audio_review_source(store,b$request$report$id,b$request$report$revision,b$request$report$hash,project_id,verify)
  line<-s$extraction_lineage;brohn_require(!is.null(line),"Media review cannot infer a video link from a filename or timestamp.")
  extraction<-brohn_audio_extraction_record(store,line$extraction$id,project_id,verify)
  brohn_require(.brohn_mr_same(.brohn_mr_ref(extraction),line$extraction),"The original audio derivation changed.")
  ledger<-Filter(function(a)identical(a$kind,"audio-frame-ledger"),extraction$body$artifacts)
  samples<-Filter(function(a)identical(a$kind,"audio-source-samples"),b$csv_objects)
  brohn_require(length(ledger)==1L&&length(samples)==1L,"Complete original audio PTS and selected-sample exports are required.")
  parent<-brohn_audio_extraction_source(store,line$parent_dataset$id,line$parent_dataset$revision,line$parent_dataset$hash,project_id,verify,FALSE)
  refs<-.brohn_mr_refs(c(s$source_objects,list(.brohn_sv_retained(store,r,"audio_review",verify)),lapply(b$csv_objects,function(x)list(hash=x$hash,bytes=x$size))))
  list(review=r,report=s$report,extraction=extraction,parent=parent$dataset,source_path=parent$source_path,
    ledger=ledger[[1L]],ledger_path=brohn_object_path(store,ledger[[1L]]$hash,verify),samples=samples[[1L]],source_objects=refs)
}
.brohn_mr_prepare_context<-function(store,audio_review_id,revision,hash,project_id,operation="media_tracks",catalog=NULL,video_stream_index=NULL,cursor_sample=NULL,verify=FALSE) {
  brohn_require(operation%in%c("media_tracks","media_review"),"Choose video track inspection or an exact media cursor.")
  s<-brohn_media_review_source(store,list(id=audio_review_id,revision=revision,hash=hash),project_id,verify)
  selected<-NULL;ref<-NULL
  if(operation=="media_tracks")brohn_require(is.null(catalog)&&is.null(video_stream_index)&&is.null(cursor_sample),"Track inspection does not select or align frames.")else {
    brohn_require(is.list(catalog)&&brohn_number(video_stream_index,0,63,TRUE),"Inspect the original video tracks before choosing one.")
    c<-brohn_media_review_record(store,catalog$id,audio_review_id,project_id,FALSE)
    brohn_require(.brohn_mr_same(.brohn_mr_ref(c),catalog)&&identical(c$body$request$operation,"media_tracks")&&
      .brohn_mr_same(c$body$request$audio_review,.brohn_mr_ref(s$review)),"This video inventory belongs to another saved audio window.")
    tracks<-Filter(function(t)t$stream_index==video_stream_index&&!isTRUE(t$attached_picture),c$body$result$tracks)
    support<-s$review$body$result$support
    brohn_require(length(tracks)==1L&&brohn_number(cursor_sample,support$first_sample,support$stop_sample-1,TRUE),"Choose an original video track and a sample within the exact saved audio interval.")
    ref<-.brohn_mr_ref(c);selected<-list(video_stream_index=as.integer(video_stream_index),cursor_sample=as.integer(cursor_sample))
  }
  request<-list(schema="brohn-media-review-job/1.0",profile=.brohn_mr_profile,operation=operation,project_id=project_id,
    audio_review=.brohn_mr_ref(s$review),report=.brohn_mr_ref(s$report),dataset=.brohn_mr_ref(s$parent),extraction=.brohn_mr_ref(s$extraction),
    report_id=s$report$id,dataset_id=s$parent$id,study_id=s$report$body$study_id,origin=s$report$body$origin,
    source=s$parent$body$source[c("hash","size")],audio_ledger=s$ledger[c("hash","size")],
    recording=s$extraction$body$result$recording,catalog=ref,selection=selected,implementation=.brohn_media_review_loaded)
  list(request=request,source=s)
}
brohn_prepare_media_review<-function(store,audio_review_id,revision,hash,project_id,operation="media_tracks",catalog=NULL,video_stream_index=NULL,cursor_sample=NULL) {
  .brohn_mr_prepare_context(store,audio_review_id,revision,hash,project_id,operation,catalog,video_stream_index,cursor_sample)$request
}
brohn_queue_media_review<-function(store,audio_review_id,revision,hash,project_id,operation="media_tracks",catalog=NULL,video_stream_index=NULL,cursor_sample=NULL,retry=FALSE) {
  r<-brohn_prepare_media_review(store,audio_review_id,revision,hash,project_id,operation,catalog,video_stream_index,cursor_sample)
  brohn_enqueue_job(store,operation,r,paste0(operation,":",brohn_hash(r),if(retry)paste0(":",brohn_id("retry"))else""))
}
brohn_media_review_input<-function(store,job,verify=TRUE,require_current=TRUE) {
  r<-job$request
  brohn_fields(r,c("schema","profile","operation","project_id","audio_review","report","dataset","extraction","report_id","dataset_id","study_id","origin","source","audio_ledger","recording","catalog","selection","implementation"),label="Media review job")
  brohn_require(identical(r$schema,"brohn-media-review-job/1.0")&&identical(r$profile,.brohn_mr_profile)&&identical(job$operation,r$operation),"Use a registered saved media review.")
  context<-.brohn_mr_prepare_context(store,r$audio_review$id,r$audio_review$revision,r$audio_review$hash,r$project_id,r$operation,r$catalog,r$selection$video_stream_index,r$selection$cursor_sample,verify)
  expected<-context$request
  brohn_require(length(r$implementation)==length(.brohn_media_review_loaded)&&!anyDuplicated(names(r$implementation))&&setequal(names(r$implementation),names(.brohn_media_review_loaded))&&all(vapply(r$implementation,.brohn_mr_sha,logical(1))),"Media review implementation identity is incomplete.")
  if(!require_current)expected$implementation<-r$implementation
  if(require_current)brohn_require(all(vapply(names(r$implementation),function(p)identical(digest::digest(file=p,algo="sha256"),r$implementation[[p]]),logical(1))),"Media review implementation changed after queueing.")
  brohn_require(.brohn_mr_same(r,expected),"Media review substituted its waveform, original recording, extraction, clock or selected cursor.")
  s<-context$source;refs<-s$source_objects
  if(!is.null(r$catalog)){c<-brohn_get_entity(store,"media_review",r$catalog$id,r$catalog$revision);refs<-c(refs,list(.brohn_sv_retained(store,c,"media_review",verify)))}
  list(schema="brohn-analysis-input/1.0",operation=r$operation,project_id=r$project_id,origin=r$origin,binding=r,
    source_path=s$source_path,audio_ledger_path=s$ledger_path,source_objects=.brohn_mr_refs(refs))
}
brohn_validate_media_review<-function(result,input) {
  r<-input$binding
  brohn_require(identical(result$schema,"brohn-media-review-result/1.0")&&identical(result$profile,.brohn_mr_profile)&&identical(result$operation,r$operation)&&
    .brohn_mr_same(result$binding,r)&&.brohn_mr_same(result$source,r$source)&&.brohn_mr_same(result$audio_ledger,r$audio_ledger)&&.brohn_mr_same(result$selection,r$selection),"Saved media review changed its exact source or selection.")
  brohn_require(brohn_array(result$tracks)&&length(result$tracks)<=64L&&!anyDuplicated(vapply(result$tracks,function(x)as.numeric(x$stream_index),numeric(1)))&&
    .brohn_mr_sha(result$engine$ffprobe$sha256),"Video inventory or original probe identity is invalid.")
  for(t in result$tracks)brohn_require(brohn_number(t$stream_index,0,63,TRUE)&&brohn_number(t$width,1,3840*2160,TRUE)&&brohn_number(t$height,1,3840*2160,TRUE)&&t$width*t$height<=3840*2160&&
    brohn_text(t$time_base,32)&&grepl("^[0-9]+/[0-9]+$",t$time_base)&&identical(t$orientation,"encoded pixels, no autorotation"),"A video track has unsupported dimensions or clock identity.")
  if(r$operation=="media_tracks")brohn_require(is.null(result$mapping)&&is.null(result$coverage)&&length(result$artifacts)==0L,"An inventory cannot imply a synchronized frame.")else {
    m<-result$mapping;c<-result$coverage
    brohn_require(identical(m$policy,"original-audio-frame-pts-plus-local-sample/1.0")&&m$selected_sample==r$selection$cursor_sample&&
      m$sampling_rate==r$recording$sampling_rate&&identical(m$audio_time_base,r$recording$time_base)&&identical(m$audio_origin_pts_ticks,r$recording$source_start_pts_ticks)&&
      identical(m$physical_synchronization,"not_established"),"Media review changed its original audio-frame clock mapping.")
    brohn_require(c$status%in%c("available","ambiguous_clock","overlapping_frames","no_supported_frame")&&brohn_number(c$frame_count,1,36000,TRUE)&&
      length(result$rows)==min(100,c$frame_count)&&identical(c$policy,"declared_duration_half_open_or_exact_pts_only_no_nominal_fps_fill")&&
      length(result$artifacts)==if(c$status=="available")2L else 1L,"Video frame support or full ledger is incomplete.")
    ledger<-result$artifacts[[1L]]
    brohn_require(identical(ledger$kind,"video-frame-ledger")&&identical(ledger$path,"video-frames.csv")&&ledger$rows==c$frame_count&&
      .brohn_mr_sha(ledger$hash)&&brohn_number(ledger$size,1,16*1024^2,TRUE),"The complete video timestamp ledger changed.")
    if(c$status=="available") {
      image<-result$artifacts[[2L]];f<-result$frame_extraction
      brohn_require(brohn_number(c$frame$frame_index,0,c$frame_count-1,TRUE)&&identical(image$kind,"recorded-video-frame")&&identical(image$media_type,"image/png")&&
        .brohn_mr_sha(image$hash)&&brohn_number(image$size,1,32*1024^2,TRUE)&&.brohn_mr_sha(f$rgb24_sha256)&&
        f$frame_index==c$frame$frame_index&&f$stream_index==r$selection$video_stream_index&&f$decoded_frames_to_selection==c$frame$frame_index+1&&
        identical(f$policy,"sequential_original_rgb24_no_seek_no_autorotation")&&identical(f$decoder_sha256,result$engine$ffmpeg$sha256),"Recorded pixels lost their exact stream/frame/decoder identity.")
    }else brohn_require(is.null(c$frame)&&is.null(result$frame_extraction),"Unsupported clock coverage must not expose a guessed frame.")
  };invisible(result)
}
brohn_analyse_media_review<-function(input,scratch) {
  r<-input$binding;directory<-file.path(scratch,"artifacts")
  request<-list(schema="brohn-media-review-request/1.0",operation=r$operation,binding=r,source_path=input$source_path,source=r$source,
    audio_ledger_path=input$audio_ledger_path,audio_ledger=r$audio_ledger,recording=r$recording,selection=r$selection,output_directory=directory)
  rp<-file.path(scratch,"media-review-request.json");out<-file.path(scratch,"media-review-result.json");brohn_write_json_file(request,rp)
  child<-processx::run(brohn_python_profile("audio"),c("scripts/workers/media_review.py","--request",rp,"--output",out),timeout=300,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(out),paste("Media review returned no result.",substr(child$stderr,1,700)))
  result<-brohn_read_json_file(out,4*1024^2)
  brohn_require(child$status==0&&!identical(result$status,"error"),paste("Media review needs attention:",result$error$message))
  brohn_validate_media_review(result,input);list(media_review=result)
}
brohn_publish_media_review<-function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Publish saved media outside a writer transaction.")
  .brohn_publication_output_identity(output,.brohn_media_review_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(.brohn_mr_same(input,brohn_media_review_input(store,job))&&.brohn_mr_same(output,brohn_read_json_file(output_path)),"Media source authority or original worker output changed before publication.")
  result<-output$report$media_review;brohn_validate_media_review(result,input)
  staged<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(staged))brohn_close_publication(staged$guard,committed)},add=TRUE)
  if(length(result$artifacts))staged<-.brohn_publication_stage(store,job,lapply(result$artifacts,function(a)list(key=a$kind,kind=a$kind,
    path=brohn_checked_artifact_path(store,file.path(scratch,"artifacts",a$path),scratch),sha256=a$hash,bytes=a$size,media_type=a$media_type)))
  objects<-if(is.null(staged))list()else lapply(staged$descriptors,function(a)c(list(kind=a$kind),a[c("hash","size","media_type")]))
  id<-paste0("media-review-",job$id)
  b<-list(schema="brohn-saved-media-review/1.0",id=id,audio_review_id=input$binding$audio_review$id,report_id=input$binding$report_id,dataset_id=input$binding$dataset_id,
    study_id=input$binding$study_id,origin=input$origin,request=job$request,result=result,artifacts=objects,created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  document<-.brohn_publication_stage_json(store,job,b,file.path(scratch,"published-media-review.json"))
  receipt<-brohn_store_batch(store,function(){
    brohn_require(.brohn_mr_same(input,brohn_media_review_input(store,job,FALSE)),"Original media, saved waveform or current permission changed before publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    if(!is.null(staged)).brohn_publication_register(store,staged)
    b$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"media_review",id,b,0L,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(media_review_id=id,audio_review_id=b$audio_review_id,report_id=b$report_id,dataset_id=b$dataset_id,output_hash=b$result_object$hash))
  });committed<-TRUE;receipt
}
.brohn_mr_record_context<-function(store,id,audio_review_id,project_id,verify=FALSE) {
  r<-brohn_get_entity(store,"media_review",id)
  brohn_require(!is.null(r)&&identical(r$project_id,project_id)&&identical(r$body$audio_review_id,audio_review_id)&&identical(r$body$schema,"brohn-saved-media-review/1.0"),"Open a saved media cursor belonging to this original audio window.")
  .brohn_qexplorer_catalog(store,"media_review",id,r$revision,project_id)
  input<-brohn_media_review_input(store,list(operation=r$body$request$operation,request=r$body$request),verify,require_current=FALSE)
  brohn_validate_media_review(r$body$result,input)
  brohn_require(length(r$body$artifacts)==length(r$body$result$artifacts),"Saved media artifacts are incomplete.")
  for(i in seq_along(r$body$artifacts)) {
    a<-r$body$artifacts[[i]];original<-r$body$result$artifacts[[i]]
    brohn_require(.brohn_mr_same(a,original[c("kind","hash","size","media_type")]),"A saved media ledger or recorded image changed its identity.")
    brohn_object_path(store,a$hash,verify)
  }
  job<-brohn_get_job(store,r$body$processing$job_id)
  brohn_require(identical(job$status,"succeeded")&&identical(job$operation,r$body$request$operation)&&identical(job$result$media_review_id,r$id)&&
    identical(job$result$output_hash,r$body$result_object$hash)&&.brohn_mr_same(job$request,r$body$request),"This media cursor has no matching completed publication.")
  if(verify).brohn_sv_retained(store,r,"media_review",TRUE)
  list(record=r,input=input)
}
brohn_media_review_record<-function(store,id,audio_review_id,project_id,verify=FALSE) {
  .brohn_mr_record_context(store,id,audio_review_id,project_id,verify)$record
}

# Native source seals remain held while complete hashing runs outside Shiny.
brohn_begin_media_review_open<-function(store,record) {
  context<-.brohn_mr_record_context(store,record$id,record$body$audio_review_id,record$project_id,FALSE)
  r<-context$record;input<-context$input
  refs<-.brohn_mr_refs(c(input$source_objects,lapply(c(r$body$artifacts,list(r$body$result_object)),function(a)list(hash=a$hash,bytes=a$size))))
  guards<-list();ok<-FALSE;on.exit(if(!ok)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  files<-lapply(refs,function(a){path<-brohn_object_path(store,a$hash,FALSE);guards[[length(guards)+1L]]<<-.brohn_qexplorer_hold(path,a$bytes);list(path=path,hash=a$hash,bytes=a$bytes)})
  code<-paste(c("import hashlib,json,os,sys","for x in json.loads(sys.argv[1]):",
    " assert os.path.getsize(x['path'])==x['bytes'],'Saved media size changed'",
    " with open(x['path'],'rb') as f: assert hashlib.file_digest(f,'sha256').hexdigest()==x['hash'],'Saved media bytes changed'","print('verified')"),collapse="\n")
  process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,brohn_json(files)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  pending<-new.env(parent=emptyenv());pending$record<-r;pending$guards<-guards;pending$process<-process;pending$state<-new.env(parent=emptyenv());pending$state$active<-TRUE
  lockEnvironment(pending,bindings=TRUE);ok<-TRUE;pending
}
brohn_close_media_review<-function(view) {
  if(is.environment(view)&&environmentIsLocked(view)&&isTRUE(view$state$active)) {
    if(view$process$is_alive())view$process$kill_tree()
    for(g in view$guards).brohn_qexplorer_release(g)
    state<-view$state;state$active<-FALSE
  };invisible(NULL)
}
brohn_poll_media_review_open<-function(store,pending) {
  brohn_require(is.environment(pending)&&environmentIsLocked(pending)&&isTRUE(pending$state$active),"Reopen the retained media cursor.")
  r<-pending$record;brohn_media_review_record(store,r$id,r$body$audio_review_id,r$project_id,FALSE)
  for(g in pending$guards).Call(g$native$check,g$pointer)
  if(pending$process$is_alive())return(NULL)
  brohn_require(pending$process$get_exit_status()==0&&identical(trimws(pending$process$read_all_output()),"verified"),"The retained media source failed its complete byte verification.")
  .brohn_sv_retained(store,r,"media_review",FALSE);r
}

# Exact decimal seconds -> nearest stored sample. Half-sample ties move later.
# Fractional numerator*rate stays <=384000*999999999 (<2^53); all compared
# integers and remainders are exactly representable in this bounded profile.
brohn_media_cursor_seconds<-function(value,rate,first_sample,stop_sample) {
  brohn_require(brohn_text(value,32)&&grepl("^[0-9]{1,5}(\\.[0-9]{1,9})?$",value)&&
    brohn_number(rate,1000,384000,TRUE)&&brohn_number(first_sample,0,20000000,TRUE)&&brohn_number(stop_sample,first_sample+1,20000000,TRUE),
    "Enter audio seconds with at most nine decimal places inside the saved window.")
  parts<-strsplit(value,".",fixed=TRUE)[[1L]];whole<-as.numeric(parts[[1L]])
  fraction<-if(length(parts)>1L)parts[[2L]]else"";den<-10^nchar(fraction);num<-if(nzchar(fraction))as.numeric(fraction)else 0
  product<-num*rate;q<-floor(product/den);remainder<-product-q*den
  # Selection must be inside the source interval before rounding too.
  exact_floor<-whole*rate+q
  brohn_require(exact_floor>=first_sample&&exact_floor<stop_sample,"Choose audio time inside the exact saved window; its end is excluded.")
  sample<-exact_floor+as.numeric(2*remainder>=den)
  brohn_require(sample>=first_sample&&sample<stop_sample,"The nearest sample falls outside this window. Choose a time within its last retained sample.")
  list(sample=as.integer(sample),time_s=sub("\\.?0+$","",sprintf("%.9f",sample/rate)),time_fraction=paste0(sample,"/",rate),input_seconds=value,policy="nearest_original_sample_half_ties_later")
}
